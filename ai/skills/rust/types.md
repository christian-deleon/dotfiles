# Types — Ownership, Traits, Generics

Rust's type system is what makes the language work. Three ideas account for almost all the "fight the compiler" experience: **ownership** (every value has exactly one owner at a time), **borrowing** (you can have many shared `&T` references *or* one unique `&mut T` reference, never both), and **lifetimes** (every reference is tagged with a scope it can't outlive). Internalize those three and the borrow checker stops feeling adversarial — it's checking the same thing you'd check by hand in C++, just earlier and more reliably.

The most common AI failure mode here is reaching for `clone()` whenever a borrow check fails, `Box<dyn Trait>` whenever generics get awkward, and `Arc<Mutex<T>>` whenever two things might run at once. All three are tools that have a real place but are wrong as defaults — they pay runtime cost to bypass a design problem the type system was pointing at.

## Ownership and moves

Every value has one owner. Assigning, passing as an argument, or returning from a function **moves** ownership unless the type implements `Copy`:

```rust
let s = String::from("hi");
let t = s;             // s is moved into t — s is no longer usable
// println!("{s}");    // ERROR — borrow of moved value
println!("{t}");       // fine
```

`Copy` types (integers, floats, `bool`, `char`, fixed-size arrays of `Copy` types, `&T`) are duplicated bitwise on assignment:

```rust
let a = 5_i32;
let b = a;             // a is copied, not moved
println!("{a} {b}");   // both fine
```

A struct can be `Copy` only if all its fields are `Copy`. Derive `Copy` only when the type is cheap to copy and *would normally be passed by value in C* — small `Point { x: f64, y: f64 }` style. Don't make `String`, `Vec`, or anything heap-backed `Copy` (and you can't — they own a heap allocation, which can't be copied bitwise).

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
struct Point { x: f64, y: f64 }
```

`Clone` is the explicit, possibly-expensive duplication. `Copy` is the implicit, always-cheap one. `Copy` requires `Clone` as a supertrait.

## Borrowing — `&T` vs `&mut T`

A function that *reads* a value should take a shared reference:

```rust
fn length(s: &str) -> usize { s.len() }            // never mutates
fn first(v: &[i32]) -> Option<&i32> { v.first() }
```

A function that *mutates* takes a unique mutable reference:

```rust
fn push_zero(v: &mut Vec<i32>) { v.push(0); }
```

A function that needs to *own* takes by value:

```rust
fn into_chars(s: String) -> Vec<char> { s.chars().collect() }
```

The rule the borrow checker enforces: at any moment, a value has **either** any number of `&T` (shared) **or** exactly one `&mut T` (unique). Never both. Never two `&mut`.

This is what makes data races impossible — a thread holding `&mut T` is the only thing that can see `T`'s data at all, and `&T` guarantees no one else can mutate it.

### Parameter-type cheat sheet

| You want to | Parameter type | Notes |
|---|---|---|
| Read a string | `&str` | `&String` works but accepts strictly less; always prefer `&str` |
| Read a path | `impl AsRef<Path>` (or `&Path`) | `AsRef` accepts `&str`, `&Path`, `&PathBuf`, `String`, etc. |
| Read a slice of things | `&[T]` | Not `&Vec<T>` — slices accept arrays, vec, and slices |
| Build/own a string | `String` (or `impl Into<String>` to be flexible) | Caller decides whether to clone |
| Modify the value | `&mut T` | |
| Take ownership and consume | `T` | |
| Maybe own, maybe borrow | `Cow<'_, T>` | See below; for return types more often than params |
| Generic function over `T` and `&T` | `impl Borrow<T>` | `HashMap::get` is the canonical example |

`&str` is the right parameter type for the *vast* majority of string-reading functions. Take `&str`, return `String` (or `&str` with a lifetime if you can).

### Return types

Return owned types from functions that produce data:

```rust
fn build_name(first: &str, last: &str) -> String {
    format!("{first} {last}")
}
```

Return borrowed types only when the lifetime is clearly tied to an input:

```rust
fn longest<'a>(a: &'a str, b: &'a str) -> &'a str {
    if a.len() > b.len() { a } else { b }
}
```

Never return a reference to a local — it would dangle, and the borrow checker rejects it.

## Lifetimes

A lifetime is a compile-time annotation that says "this reference is valid for at least this region of code." Most lifetimes are inferred (elision rules — see below); you only name them when the compiler can't.

### Elision

Three rules cover most cases. If they fully resolve the function's reference types, you don't write lifetimes:

1. Each elided lifetime in the inputs gets its own fresh lifetime: `fn f(a: &str, b: &str)` → `fn f<'a, 'b>(a: &'a str, b: &'b str)`.
2. If there's exactly one input lifetime, it's used for all output lifetimes.
3. If there are multiple input lifetimes but one of them is `&self` or `&mut self`, that lifetime is used for all output lifetimes.

When you need explicit lifetimes, name them by what they relate:

```rust
fn first_word<'a>(s: &'a str) -> &'a str {
    s.split_whitespace().next().unwrap_or("")
}

// Tie output to one of two inputs:
fn pick<'a>(a: &'a str, b: &str) -> &'a str { a }
```

### Lifetime bounds on generics

```rust
fn longest<'a, T: AsRef<str>>(items: &'a [T]) -> Option<&'a str> {
    items.iter().map(|t| t.as_ref()).max_by_key(|s| s.len())
}
```

`'static` is the special lifetime meaning "for the duration of the program." String literals, `'static` references, and `Arc<str>` are common bearers. Don't reach for `T: 'static` reflexively — it's a strong bound that excludes most borrowed data. You usually want `T: 'a` for some named lifetime, or to design the function not to need it.

### When the borrow checker is right

Common patterns it (rightly) rejects:

- Returning a reference to a local variable.
- Holding `&v` and calling `v.push(x)` (the push may reallocate the buffer, invalidating the reference).
- Iterating over a collection while mutating it.
- Two mutable references to the same slice.

Fixes:

- Return an owned value (`String`, `Vec<T>`).
- Use `&v[..]` slice indexing, then push *after* dropping the borrow.
- `split_at_mut`/`chunks_mut`/`iter_mut` give disjoint mutable references safely.
- `let len = v.len();` to copy out the data you needed before mutating.

If you're tempted to clone to silence the borrow checker, pause. The clone is usually masking either (a) the wrong parameter type (took `String`, should be `&str`) or (b) a design where two pieces of code shouldn't both own the same data — pick one owner.

## Smart pointers

Owning, borrowing, and Copy cover most of the design space. The smart-pointer types fill the gaps:

| Type | What it is | When to reach for it |
|---|---|---|
| `Box<T>` | Heap-allocated single owner | Recursive types (`enum Tree { Leaf, Node(Box<Tree>, Box<Tree>) }`); trait objects (`Box<dyn Trait>`); large `T` you want off the stack |
| `Rc<T>` | Reference-counted shared owner (single-threaded) | Tree/graph structures with multiple references; **never across threads** (not `Send`) |
| `Arc<T>` | Atomically-reference-counted shared owner | The multi-threaded / async version of `Rc`; what you'll actually use 99% of the time |
| `Cell<T>` | Interior mutability for `Copy` types | Counters, flags inside `&self` methods; cheap, no runtime checks |
| `RefCell<T>` | Interior mutability for non-`Copy` types (single-threaded) | When you logically need `&mut` through `&self`; runtime panic if you violate borrow rules |
| `Mutex<T>` (std or tokio) | Interior mutability across threads with a lock | Multi-writer shared state |
| `RwLock<T>` | Many readers OR one writer, across threads | When reads dominate writes |
| `Atomic*` (`AtomicUsize`, `AtomicBool`, etc.) | Lock-free single-value mutability | Counters, flags, simple state across threads |
| `Cow<'_, T>` | Either borrowed `&T` or owned `T` | "Usually borrow, occasionally own" — return type for parsers that mostly slice but sometimes allocate |
| `Pin<P>` | Pinned-in-memory pointer | Self-referential structs, futures generated by `async fn`; rarely written by hand |

### `Box<T>` — boxed values

```rust
let x: Box<i32> = Box::new(5);
println!("{}", *x);   // automatically dereferences

// Recursive type
enum List<T> {
    Nil,
    Cons(T, Box<List<T>>),
}

// Trait object
let printer: Box<dyn std::fmt::Display> = Box::new(42);
```

`Box<T>` is the simplest indirection — one heap allocation, one owner. Use it when you need a value to live on the heap (recursion, large types) or when you need dynamic dispatch (`dyn Trait`).

### `Rc<T>` and `Arc<T>` — shared ownership

```rust
use std::sync::Arc;

let shared = Arc::new(String::from("hello"));
let a = Arc::clone(&shared);   // cheap — bumps refcount
let b = Arc::clone(&shared);
std::thread::spawn(move || println!("{a}"));
std::thread::spawn(move || println!("{b}"));
```

`Arc::clone(&x)` (not `x.clone()`) is the conventional way to bump the refcount — makes it clear at the call site that it's a cheap operation, not a deep clone.

`Rc<T>` is the same shape but single-threaded (no atomics, slightly cheaper). Use it for trees/DAGs where the data lives on one thread. If you're not sure whether you'll go multi-threaded, just use `Arc<T>` — the overhead is small and you avoid a future rewrite.

For shared *immutable* string or byte data, prefer the slice forms over `Arc<String>`/`Arc<Vec<u8>>`:

```rust
let s: Arc<str> = Arc::from("hello");
let b: Arc<[u8]> = Arc::from(&b"\x00\x01\x02"[..]);
```

These are one allocation, not two (`Arc<String>` is `Arc` → `String` → heap buffer; `Arc<str>` is `Arc` → heap buffer).

### Interior mutability — `Cell`, `RefCell`, `Mutex`, `RwLock`

The borrow checker is conservative. Sometimes you logically need to mutate through `&self` (e.g., a cache, a counter). Interior mutability types let you do this safely:

| Type | Mutation API | Cost | Single-thread / multi-thread |
|---|---|---|---|
| `Cell<T>` | `.get()` (returns a Copy), `.set(v)`, `.replace(v)` | Free — no lock, no refcount | Single-thread (`!Sync`) |
| `RefCell<T>` | `.borrow()`, `.borrow_mut()`; panics on violation | Runtime borrow check | Single-thread (`!Sync`) |
| `Mutex<T>` | `.lock()` — returns a `MutexGuard` | OS-level lock | Multi-thread |
| `RwLock<T>` | `.read()`, `.write()` | Reader-writer lock | Multi-thread |
| `Atomic*` | `.load()`, `.store()`, `.fetch_add()`, etc. with `Ordering` | Lock-free | Multi-thread |
| `OnceLock<T>` | `.get_or_init(|| ...)` | Write-once | Multi-thread (also `OnceCell` for single-thread) |
| `LazyLock<T>` | `*LAZY` deref triggers init | Write-once with init closure | Multi-thread (also `LazyCell` for single-thread) |

`std::sync::LazyLock` and `OnceLock` replaced the `lazy_static!` macro and the `once_cell` crate respectively, stable in `std` since Rust 1.80. New code should not use those external crates:

```rust
use std::sync::LazyLock;
use std::collections::HashMap;

static MIME_TYPES: LazyLock<HashMap<&str, &str>> = LazyLock::new(|| {
    HashMap::from([
        ("html", "text/html"),
        ("json", "application/json"),
    ])
});
```

### `Arc<Mutex<T>>` — when to use it, when to avoid it

`Arc<Mutex<T>>` is the reflex shape for "shared mutable state across threads." It works, but it's also the structure of most concurrency bugs (deadlocks, lock contention, lock-held-across-await footguns). Reach for it only after you've ruled out:

- **One owner with a channel.** `tokio::sync::mpsc::channel` — one task owns the state, others send messages.
- **`Arc<RwLock<T>>` if reads dominate.** Many readers, occasional writer.
- **Atomic types** for single-value state.
- **Per-task copies** (`Arc<T>` of an *immutable* value, or `Clone` for cheap types).
- **`std::thread::scope`** if the threads are short-lived enough to borrow from the stack.

When you do use `Arc<Mutex<T>>`, keep the critical section **short** and never hold the guard across a yield point (`.await` for async, blocking I/O for sync). If the guard must cross `.await`, use `tokio::sync::Mutex` instead — its guard is `Send` and async-aware.

## Traits

Traits are interfaces. Implementing a trait means a type promises to provide a set of methods.

```rust
pub trait Greet {
    fn greet(&self) -> String;
    fn shout(&self) -> String {
        self.greet().to_uppercase()    // default method body
    }
}

pub struct English;
pub struct Spanish;

impl Greet for English { fn greet(&self) -> String { "hello".into() } }
impl Greet for Spanish { fn greet(&self) -> String { "hola".into() } }

fn say<G: Greet>(g: &G) { println!("{}", g.greet()); }
```

### Standard library traits worth knowing

| Trait | What it means | Derive? |
|---|---|---|
| `Debug` | `{:?}` formatting; should round-trip enough info for debugging | Yes (`#[derive(Debug)]`) |
| `Clone` | Explicit deep copy via `.clone()` | Yes |
| `Copy` | Implicit bitwise copy on assignment | Yes (only if all fields are `Copy`) |
| `PartialEq`, `Eq` | `==` and `!=` (Eq is the "no NaN-like values" stricter version) | Yes |
| `PartialOrd`, `Ord` | `<`, `>`, `cmp` | Yes |
| `Hash` | For use as a key in `HashMap`/`HashSet` | Yes |
| `Default` | `T::default()` returns a "zero value" | Yes (when fields' defaults compose) |
| `Display` | User-facing `{}` formatting | No — write by hand; users see this |
| `From<T>` / `Into<U>` | Conversion (implement `From`, get `Into` free) | No |
| `TryFrom<T>` / `TryInto<U>` | Fallible conversion returning `Result` | No |
| `AsRef<T>` / `AsMut<T>` | Cheap reference conversion (e.g., `&str` from `&String`) | No |
| `Borrow<T>` | Like `AsRef` but with `Hash`/`Eq` consistency for use as keys | No |
| `Iterator` | `next()` → `Option<Item>`; everything else is default methods | No |
| `IntoIterator` | A type that *can produce* an iterator (used by `for x in things`) | No |
| `Send` / `Sync` | Auto-traits — `T` can be moved/shared across threads | Auto |

For new types you'll publish:

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct UserId(u64);
```

Always start with `Debug`. Add `Clone` if the type is meaningfully cheap to clone. Add `PartialEq`/`Eq`/`Hash` if it's an ID, key, or value type. Add `Default` only when there's a meaningful zero-value.

### `Display` is not `Debug`

```rust
use std::fmt;

impl fmt::Display for UserId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "user:{}", self.0)
    }
}
```

`{}` (`Display`) is for end users. `{:?}` (`Debug`) is for developers. Never derive `Display`; write it deliberately.

### Trait objects vs generics — `dyn Trait` vs `impl Trait`

Generics with trait bounds = **static dispatch**. The compiler generates a copy of the function for each concrete type. Faster, but bigger binary.

```rust
fn handle<H: Handler>(h: H) { h.process(); }
fn handle(h: impl Handler) { h.process(); }            // sugar for the above
```

Trait objects (`dyn Trait`) = **dynamic dispatch**. One function, a vtable lookup per call. Lets you store heterogeneous types in one collection.

```rust
fn handle(h: &dyn Handler) { h.process(); }
let handlers: Vec<Box<dyn Handler>> = vec![Box::new(A), Box::new(B)];
```

Pick by what you need:

| Need | Pick |
|---|---|
| One implementing type at a time, performance matters | `impl Trait` / generic |
| Heterogeneous collection of trait impls | `Vec<Box<dyn Trait>>` |
| Trait object stored in a struct field | `Box<dyn Trait>` (owned) or `Arc<dyn Trait + Send + Sync>` (shared) |
| Returning different concrete types from different branches | `Box<dyn Trait>` (or refactor — see below) |
| Plugin API where consumers register implementations at runtime | `dyn Trait` |

Generics are the default. Reach for `dyn` when you specifically need a single concrete pointer type that erases the implementor.

#### `impl Trait` in return position

```rust
fn make_iter() -> impl Iterator<Item = i32> {
    (0..10).filter(|n| n % 2 == 0)
}
```

This returns *some* iterator the compiler picks, with the concrete type hidden. As of Edition 2024, RPIT (return-position impl trait) captures input lifetimes by default — a small but meaningful behavior change. The reference for the precise rules: [Rust reference](https://doc.rust-lang.org/reference/types/impl-trait.html).

When you need to return different concrete types from different branches, `impl Trait` won't work (you can only return one concrete type). Two ways forward:

```rust
// 1. Box it
fn pick(cond: bool) -> Box<dyn Iterator<Item = i32>> {
    if cond { Box::new(0..10) } else { Box::new([1, 2, 3].into_iter()) }
}

// 2. Use Either / itertools::Either to keep static dispatch
use itertools::Either;
fn pick(cond: bool) -> impl Iterator<Item = i32> {
    if cond { Either::Left(0..10) } else { Either::Right([1, 2, 3].into_iter()) }
}
```

#### Dyn compatibility

Not every trait can be made into `dyn Trait`. A trait is **dyn-compatible** (formerly "object-safe") when its methods don't refer to `Self` by value, don't have generic parameters, and don't return `impl Trait`. If you need a trait that works as `dyn Trait`:

```rust
pub trait Handler {
    fn process(&self);                   // OK — &self, no generics
    fn name(&self) -> &str;              // OK
    // fn finish(self);                  // NOT OK — Self by value
    // fn do_with<T>(&self, x: T);       // NOT OK — generic parameter
}
```

For traits with `async fn`, see "async traits" below — they're not dyn-compatible by default.

## Generics

Type parameters introduce type variables that get filled in at use:

```rust
fn first<T>(xs: &[T]) -> Option<&T> { xs.first() }

struct Pair<A, B> { left: A, right: B }
```

### Bounds

A bound says "this type parameter must implement these traits":

```rust
fn max<T: Ord>(xs: &[T]) -> Option<&T> { xs.iter().max() }
fn pair_clone<T: Clone>(x: &T) -> (T, T) { (x.clone(), x.clone()) }
```

Multiple bounds:

```rust
fn dump<T: Clone + std::fmt::Debug>(x: T) { println!("{:?} {:?}", x.clone(), x); }
```

When the bound list gets long, use a `where` clause for readability:

```rust
fn process<I, F, R>(iter: I, f: F) -> Vec<R>
where
    I: IntoIterator,
    F: Fn(I::Item) -> R,
    R: Clone,
{
    iter.into_iter().map(f).collect()
}
```

### Generic constants and types

```rust
fn buffer<const N: usize>() -> [u8; N] { [0; N] }

let b: [u8; 16] = buffer();   // N inferred to 16
```

Const generics are stable for primitive types since Rust 1.51; richer support (complex expressions, generic-const-exprs) is still nightly.

### Associated types vs generic parameters on traits

Use associated types when each implementing type has *one* natural choice:

```rust
trait Iterator {
    type Item;
    fn next(&mut self) -> Option<Self::Item>;
}
```

A type can implement `Iterator` only once — its `Item` is determined by the implementing type. This is what you want for `Iterator`, `IntoIterator`, `Future` (which has `type Output`), etc.

Use a generic parameter on the trait when a type might implement it *multiple times* with different choices:

```rust
trait From<T> {
    fn from(value: T) -> Self;
}

impl From<i32> for String { fn from(value: i32) -> Self { value.to_string() } }
impl From<f64> for String { fn from(value: f64) -> Self { value.to_string() } }
```

`String` implements `From<i32>` AND `From<f64>` — a generic parameter makes this work.

Rule of thumb: associated types are most traits; generic-on-trait is for conversion traits and a handful of others.

### GATs — generic associated types (1.65+)

GATs let an associated type itself be generic. The canonical use is lending iterators:

```rust
trait LendingIterator {
    type Item<'a> where Self: 'a;
    fn next(&mut self) -> Option<Self::Item<'_>>;
}
```

Most code never needs to write a GAT. If you do, it's usually because you need to return a reference whose lifetime depends on `&mut self` — which a regular `Iterator` can't do. The reference docs cover the corner cases; reach for GATs only when a regular associated type can't express the relationship.

## The newtype pattern

A tuple struct around a primitive gives you a distinct type at zero runtime cost:

```rust
pub struct UserId(pub u64);
pub struct OrderId(pub u64);

fn get_user(id: UserId) -> User { /* ... */ }

let uid = UserId(123);
let oid = OrderId(456);
get_user(oid);   // ERROR — distinct types
```

Use this freely for IDs, currencies, units, anything you don't want to accidentally mix. Combine with `Display`/`From`/`TryFrom` to make conversions explicit and well-typed.

A common pattern is a private inner field plus public constructors:

```rust
pub struct EmailAddress(String);

impl EmailAddress {
    pub fn parse(raw: &str) -> Result<Self, ParseError> {
        if !raw.contains('@') { return Err(ParseError::NoAt); }
        Ok(Self(raw.to_string()))
    }
    pub fn as_str(&self) -> &str { &self.0 }
}
```

Now the only way to construct an `EmailAddress` is through the validating constructor — "parse, don't validate" in type form.

## `From` / `Into` / `TryFrom` / `TryInto`

Always implement `From`, never `Into`. `Into` is generated for free:

```rust
impl From<&str> for UserId {
    fn from(s: &str) -> Self { UserId(s.parse().expect("not a u64")) }
}

let uid: UserId = "123".into();   // works because of the From impl
fn f(_: impl Into<UserId>) {}
f("123");                          // works
f(UserId(5));                      // works
```

`TryFrom`/`TryInto` for fallible conversion — the canonical use is parsing and bounded conversions:

```rust
impl TryFrom<u64> for SmallNum {
    type Error = OutOfRange;
    fn try_from(value: u64) -> Result<Self, Self::Error> {
        if value > 100 { Err(OutOfRange) } else { Ok(SmallNum(value as u8)) }
    }
}
```

`Into<T>` as a parameter bound makes APIs flexible without forcing the caller to allocate:

```rust
fn save(name: impl Into<String>) {
    let name: String = name.into();
    // ...
}

save("hello");                  // accepts &str
save(String::from("hello"));    // accepts String
```

## `AsRef`, `Borrow`, `Cow`

`AsRef<T>` is the "cheap reference conversion" trait — implementations are zero-cost reference-to-reference conversions:

```rust
fn read_file(path: impl AsRef<Path>) -> io::Result<String> {
    std::fs::read_to_string(path.as_ref())
}

read_file("config.toml");                        // &str → &Path
read_file(Path::new("config.toml"));             // &Path → &Path
read_file(PathBuf::from("config.toml"));         // &PathBuf → &Path
```

`Borrow<T>` is similar but adds `Hash`/`Eq`/`Ord` consistency — the borrowed and owned forms must produce the same hash and compare equal. Used by `HashMap::get` so you can look up an `&str` in a `HashMap<String, V>`:

```rust
let mut m: HashMap<String, i32> = HashMap::new();
m.insert("alice".into(), 1);
m.get("alice");        // works — &str borrows as the same key &String would
```

`Cow<'_, T>` (clone-on-write) holds either a borrow or an owned value. Use it when a function *usually* returns a slice of its input but *occasionally* needs to allocate:

```rust
fn normalize(s: &str) -> Cow<'_, str> {
    if s.contains('\r') {
        Cow::Owned(s.replace('\r', ""))
    } else {
        Cow::Borrowed(s)
    }
}
```

If the input is already clean, you return a `Cow::Borrowed` (zero allocation). If you have to fix it, you allocate once. Callers can treat either uniformly via deref.

## Async traits

`async fn` in trait methods stabilized in Rust 1.75 (December 2023). The mental model:

```rust
trait Store {
    async fn get(&self, key: &str) -> Option<String>;
    async fn set(&self, key: &str, value: String);
}
```

This is sugar for a method returning `impl Future<Output = …>`. Two real-world pitfalls:

1. **`Send` bounds.** The returned future is not automatically `Send`. If you `tokio::spawn` something that calls these methods (multi-threaded runtime), the compiler will complain. Fix with the `trait_variant` macro to generate a `Send`-flavored parallel trait:

   ```rust
   #[trait_variant::make(Store: Send)]
   pub trait LocalStore {
       async fn get(&self, key: &str) -> Option<String>;
   }
   ```

   Or use explicit return-position impl trait with bounds:

   ```rust
   trait Store {
       fn get(&self, key: &str) -> impl Future<Output = Option<String>> + Send;
   }
   ```

2. **Not dyn-compatible.** A trait with `async fn` cannot be made into `dyn Trait`. If you need dynamic dispatch over an async trait, use the `async-trait` crate (which still works fine — it boxes the future):

   ```rust
   #[async_trait::async_trait]
   pub trait Store: Send + Sync {
       async fn get(&self, key: &str) -> Option<String>;
   }

   let store: Box<dyn Store> = Box::new(MyStore);
   ```

The community direction is "use `async fn` in traits directly when you can, fall back to `async-trait` for `dyn` cases." Don't reach for `async-trait` everywhere just because it's familiar; the stable native syntax is cheaper at the call site.

## `#[non_exhaustive]`

Marks a public type as "may be extended in the future":

```rust
#[non_exhaustive]
pub enum Event {
    Click,
    Scroll,
    KeyPress(char),
}

#[non_exhaustive]
pub struct Config {
    pub host: String,
    pub port: u16,
}
```

Consequences:

- Downstream `match Event { … }` *must* include a `_ => …` arm — adding a new variant won't break their code.
- Downstream code can't construct `Config` with a struct literal `Config { host, port }` — it must use a builder or constructor function. Adding a new field won't break them.

Add `#[non_exhaustive]` to any public enum or struct you expect to evolve. It's free at the source site and saves you from a major version bump.

## Anti-patterns

| Don't | Do |
|---|---|
| `.clone()` to dodge the borrow checker | Adjust the parameter type (`&T` vs `T`), or use `Cow`, or restructure ownership |
| `String` parameters when you only read | `&str` (or `impl AsRef<str>` for flexibility) |
| `&Vec<T>` / `&String` parameters | `&[T]` / `&str` |
| `Vec<&str>` returned with a local-only lifetime | Return `Vec<String>`, or `Vec<&'a str>` borrowed from input |
| `Box<dyn Error>` as your public error type | `thiserror` enum (library) or `anyhow::Error` (app) — see [errors.md](errors.md) |
| `Arc<Mutex<T>>` reflex | Channels, scoped threads, `RwLock`, or atomics first |
| Holding `std::sync::Mutex` across `.await` | `tokio::sync::Mutex`, or scope the guard inside a non-async block |
| `lazy_static!` macro | `LazyLock<T>` from `std::sync` |
| `once_cell::sync::OnceCell` | `OnceLock<T>` from `std::sync` |
| `rand::thread_rng()` | `rand::rng()` (renamed in 0.9) |
| `Box<dyn Trait>` everywhere | Generics + `impl Trait` first; `dyn` for heterogeneous storage |
| Derive `Display` (you can't anyway, but the impulse to copy `Debug`) | Write `Display` deliberately — it's the user-facing format |
| `unwrap()` after a borrow assertion | `expect("invariant: …")` with a real explanation, or proper error handling |
| Generic functions with kitchen-sink bounds (`T: Clone + Debug + Default + Send + Sync`) | The minimum bounds the function actually uses |
| `T: 'static` bound when `T: 'a` would do | Tie the bound to the actual lifetime needed |
| Returning `Vec<Box<dyn Trait>>` from a hot path | Return an iterator (`impl Iterator<Item = …>`); only collect when needed |
| `if let Some(x) = opt { x } else { return; }` | `let Some(x) = opt else { return; };` |
| `match x { Some(n) => f(n), None => panic!() }` | `x.expect("invariant: …")` |
| Skipping `#[non_exhaustive]` on public enums you'll evolve | Add it; adding variants becomes non-breaking |
| `#[derive(Copy, Clone)]` on heap-backed types | Derive only on cheap, bitwise-copyable types |
| `Arc<String>` / `Arc<Vec<u8>>` | `Arc<str>` / `Arc<[u8]>` — one allocation instead of two |
