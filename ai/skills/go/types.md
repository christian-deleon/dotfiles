# Types, Generics, Interfaces

Go's type system is small by design: structs, interfaces, named types, generics (since 1.18), and a handful of built-ins (`map`, `chan`, slice, array, function). The 2026 baseline assumes generics are normal — they've been mature for years, the stdlib uses them (`slices`, `maps`, `cmp`, `iter`, `sync.OnceValue`), and the Go team approved **generic methods** in March 2026 (implementation in flight). Iterators (`iter.Seq[T]`, 1.23+) and generic type aliases (1.24+) are the most recent additions.

The most common AI failure mode here is making *everything* generic. Generics are right when the function body is identical across N types; if the bodies differ, the right answer is still a small interface. The second most common failure is producer-side interface definition ("Java-style") — define interfaces in the **consumer** that needs them, not next to the implementation.

## The single rule

> If the function body would be **identical** across N types, use a **type parameter**. If the behavior **differs**, use a (small) **interface**. If only one concrete type ever calls it, use **neither** and take the concrete type.
> — Robert Griesemer / Ian Lance Taylor's framing, paraphrased.

Apply the rule before reaching for either tool.

## Modern syntax baseline

| Use | Don't use |
|---|---|
| `any` | `interface{}` |
| `cmp.Ordered`, `cmp.Compare`, `cmp.Or` (stdlib, 1.21+) | `golang.org/x/exp/constraints.Ordered` |
| `func Keys[K comparable, V any](m map[K]V) []K` | `func Keys(m map[string]any) []string` repeated per type |
| `iter.Seq[T]` / `iter.Seq2[K,V]` return types | unbounded slice returns when streaming |
| Type alias `type Set[T comparable] = map[T]struct{}` (1.24+) | redeclaring the same map type in every package |
| `errors.AsType[*os.PathError](err)` (1.26+) | declare-then-pass-pointer `var pe *os.PathError; errors.As(err, &pe)` (still legal) |

## Structs

```go
type User struct {
	ID        UserID
	Email     string
	CreatedAt time.Time
}
```

Conventions:

- **Exported fields are uppercase**, unexported lowercase. The compiler enforces it.
- **JSON / SQL tags** colocated with fields: `Email string \`json:"email" db:"email"\``.
- **Don't embed `sync.Mutex` in an exported struct** — callers can copy it, breaking the lock. Use an unexported field:
  ```go
  type Cache struct {
      mu    sync.Mutex
      items map[string]item
  }
  ```
- **`go vet`'s `copylocks` check** catches mutex copying. Listen to it.

### Named types vs type aliases

```go
type UserID int        // distinct type; UserID(42) needed to convert
type Username = string // alias; identical to string everywhere
```

- **Named types** introduce a distinct type with its own method set. Use for domain primitives where mixing would be a bug (`UserID`, `OrderID`, `Cents`).
- **Type aliases** (`= T`) are exactly the same type. Use sparingly — usually for refactoring (rename without breaking callers) or shortening a complex generic instantiation.

### Generic type aliases (1.24+)

```go
type Result[T any] = struct {
    Value T
    Err   error
}

type Set[T comparable] = map[T]struct{}
```

Useful for reducing visual noise when a complex parameterized type appears repeatedly. Don't over-use — they're aliases, not new types, so `Set[string]` and `map[string]struct{}` are interchangeable to the compiler. If you wanted distinctness, declare a named type instead.

### Pointer vs value receivers

```go
func (u User) Name() string         // value receiver — copies User
func (u *User) SetName(n string)    // pointer receiver — mutates
```

Rules:

- **If the method mutates the receiver, use a pointer.** Always.
- **If the struct embeds a `sync.Mutex`, `sync.WaitGroup`, `bytes.Buffer`, etc., use a pointer.** Those types must not be copied.
- **If the struct is large** (rule of thumb: more than ~64 bytes / not fitting in a CPU cache line), use a pointer.
- **Otherwise, value receiver is fine** for small immutable types — but **consistency matters**: if any method on `T` uses a pointer receiver, *all* methods should.

When in doubt, pointer.

### Slices, maps, channels

These are reference-like types (technically: a slice is a struct with a pointer, length, and capacity; a map and channel are pointers under the hood). Important consequences:

- **Pass by value, mutate through the value.** Appending to a slice in a function may or may not be visible to the caller depending on capacity:
  ```go
  func appendOne(s []int) { s = append(s, 1) }
  // caller's view of s is unchanged if append fit in cap; updated only via the return value.
  ```
  Always **return** an updated slice. Don't try to mutate it in place via the parameter.
- **`nil` slices** are valid and preferred over `[]T{}`. `len(nil) == 0`, `append` works, `range` is empty. Difference matters only at the JSON boundary: `nil` slice encodes as `null`; `[]T{}` encodes as `[]`. Pick deliberately.
- **`nil` maps** are read-only — writing to one panics. Always `make(map[K]V)` before writing.
- **Slice-of-slice gotcha** — `b := a[:3]` shares backing storage with `a`. Mutating `b[0]` mutates `a[0]`. If you need an independent copy: `b := slices.Clone(a[:3])`.

## Interfaces

The most-important Go rule: **define the interface where it's used, not where the implementation lives.** Java/.NET tradition is the opposite. Bill Kennedy and Dave Cheney both call this out as the most common port-of-Java-idioms mistake.

```go
// in package user — the CONSUMER:
type UserStore interface {
	Get(ctx context.Context, id UserID) (User, error)
}

type Service struct {
	store UserStore
}

func (s *Service) FindByID(ctx context.Context, id UserID) (User, error) {
	return s.store.Get(ctx, id)
}

// in package postgres — the IMPLEMENTATION:
type Repository struct { /* ... */ }

func (r *Repository) Get(ctx context.Context, id UserID) (user.User, error) { /* ... */ }
// Repository satisfies user.UserStore implicitly — no `implements` keyword.
```

Why:

- **The consumer knows what it needs.** `user.Service` only uses `Get`; declaring a 12-method `UserStore` in the postgres package burdens every consumer.
- **Adding a method to the implementation doesn't change the interface** that consumers depend on.
- **No naming collision.** Many packages can each declare their own `UserStore` interface with exactly the methods they need.

### Small interfaces

The stdlib model: `io.Reader`, `io.Writer`, `fmt.Stringer`, `error`. One or two methods. If you find yourself declaring an interface with five methods, you almost certainly want to split it.

The Postel formulation: *be liberal in what you accept, conservative in what you return*. Accept the smallest interface that does the job:

```go
// Bad: requires the full *os.File even though we only Read
func parse(f *os.File) (*Doc, error)

// Good: accepts anything Readable
func parse(r io.Reader) (*Doc, error)
```

### "Accept interfaces, return structs"

The 2026 nuance: this is a **heuristic, not dogma**. Returning `error` (an interface) is always fine and frequently right. Returning a stdlib interface (`io.Reader`, `http.Handler`) is fine. Returning a project-specific interface is usually wrong — define the interface in the *next* consumer down the chain.

### Don't prefix with "I"

`type IUserStore interface` — wrong. Go convention is `UserStore`, and the consumer can disambiguate by package: `user.UserStore` vs `postgres.Repository`.

### `error` is an interface

```go
type error interface {
	Error() string
}
```

Any type implementing `Error() string` satisfies `error`. See [errors.md](errors.md) for the full pattern.

### `fmt.Stringer`

The de-facto "human-readable representation" interface. `fmt.Println(x)` calls `x.String()` if defined:

```go
func (u UserID) String() string {
	return fmt.Sprintf("user-%d", u)
}
```

Pair with the `Secret` redaction pattern from [web.md](web.md).

### Type assertions and type switches

```go
// Single-type check
if u, ok := v.(*User); ok {
	// v is *User
}

// Multi-arm dispatch
switch v := i.(type) {
case *User:
	// v is *User
case *Group:
	// v is *Group
default:
	// neither
}

// "Will panic on mismatch" — only when the panic is the desired behavior
u := v.(*User)
```

Don't use naked `v.(T)` (panicking form) outside of code that *should* panic on type mismatch — e.g., `interface{}` returned from a callback that's documented to always be `T`.

### Embedding

```go
type Animal struct {
	Name string
}

func (a Animal) Describe() string { return "I am " + a.Name }

type Dog struct {
	Animal              // embedding
	Breed string
}

d := Dog{Animal: Animal{Name: "Rex"}, Breed: "labrador"}
d.Describe()           // → "I am Rex"
d.Name                 // → "Rex"
```

Embedding promotes the inner type's fields and methods. Use for:

- **Composition with code reuse** when the embedded type's API is what callers want.
- **Implementing an interface by embedding a partial implementation** (e.g., embed `http.HandlerFunc` to gain `ServeHTTP`).
- **Interface composition**:
  ```go
  type ReadWriter interface {
      io.Reader
      io.Writer
  }
  ```

Don't embed for casual code sharing — it makes the API surface larger and can shadow methods unexpectedly. **Never embed `sync.Mutex` in an exported struct** (callers can copy it).

## Generics

### Type parameters on functions

```go
func Map[T, U any](xs []T, f func(T) U) []U {
	out := make([]U, len(xs))
	for i, x := range xs {
		out[i] = f(x)
	}
	return out
}

func Keys[K comparable, V any](m map[K]V) []K {
	out := make([]K, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
```

Common constraints:

| Constraint | Allows |
|---|---|
| `any` | Anything |
| `comparable` | Anything supporting `==` (includes interface types, but those panic at runtime if dynamic type isn't comparable) |
| `cmp.Ordered` | Integers, floats, strings (1.21+, stdlib) |
| Custom union: `interface { int \| int64 \| float64 }` | Listed types (and types whose underlying type is one of them, with `~int`) |

`x/exp/constraints` is mostly redundant in 2026 — `cmp.Ordered` and `comparable` cover the common cases. Use `constraints.Signed` / `Unsigned` only when you need the specific integer-family union.

### Type parameters on types

```go
type Stack[T any] struct {
	items []T
}

func (s *Stack[T]) Push(x T)   { s.items = append(s.items, x) }
func (s *Stack[T]) Pop() (T, bool) {
	if len(s.items) == 0 {
		var zero T
		return zero, false
	}
	last := s.items[len(s.items)-1]
	s.items = s.items[:len(s.items)-1]
	return last, true
}
```

The zero-value idiom `var zero T` is how you express "the zero value of whatever T is."

### Generic methods (March 2026 — in flight)

The original Go-generics design forbade generic methods (methods couldn't introduce their own type parameters). Approved in March 2026 reversing the earlier rejection; implementation is in flight but not stable as of May 2026.

Until shipped:

```go
// Won't compile (yet):
func (s *Set[T]) Map[U any](f func(T) U) *Set[U] { ... }

// Workaround — package-level generic function:
func MapSet[T, U comparable](s *Set[T], f func(T) U) *Set[U] { ... }
```

Track the proposal; expect it to land in a Go 1.27 or 1.28 release.

### When generics are wrong

- **Only one type ever uses it.** Drop the type parameter; take the concrete type. The function is clearer.
- **The body differs per type.** That's what interfaces are for.
- **The constraint is `any` and you never use `T`.** That's a non-generic function in disguise; the type parameter just adds noise.
- **You want runtime polymorphism.** Generics are compile-time; the dispatched function is decided at instantiation, not call time. For runtime dispatch, you still want an interface.

## Iterators (1.23+)

Functions returning `iter.Seq[T]` or `iter.Seq2[K, V]` are first-class iterables; consumers `range` over them directly:

```go
import "iter"

// Producer
func Lines(r io.Reader) iter.Seq[string] {
	return func(yield func(string) bool) {
		scan := bufio.NewScanner(r)
		for scan.Scan() {
			if !yield(scan.Text()) {
				return
			}
		}
	}
}

// Consumer
for line := range Lines(file) {
	fmt.Println(line)
	if shouldStop(line) {
		break
	}
}
```

The function passed to `iter.Seq[T]` calls `yield(v)`; if `yield` returns `false`, the consumer broke out of the loop and the iterator should stop.

`iter.Seq2[K, V]` is the same shape with two values per yield:

```go
func Enumerate[T any](xs []T) iter.Seq2[int, T] {
	return func(yield func(int, T) bool) {
		for i, x := range xs {
			if !yield(i, x) {
				return
			}
		}
	}
}

for i, x := range Enumerate([]string{"a", "b", "c"}) {
	// ...
}
```

### When iterators are right

- **Streaming**: parsing a large file, walking a tree, paginating an API.
- **Lazy evaluation**: when consumers may `break` early.
- **Unbounded sequences**: counters, generators.
- **Memory pressure**: the iterator produces one item at a time vs. allocating a slice.

### When iterators are wrong

- The consumer always wants the whole collection. Just return a slice.
- The collection is small and known up-front. Return a slice.
- The consumer is going to `slices.Collect` it immediately. Skip the indirection — return the slice.

The stdlib pattern: `slices.Sorted(iter.Seq[T])` returns a slice (eager); `slices.Values([]T)` returns an iterator (lazy view). Choose based on caller needs.

## `unique.Make` for canonicalization (1.23+)

```go
import "unique"

type IP4 [4]byte

handle1 := unique.Make(IP4{192, 168, 0, 1})
handle2 := unique.Make(IP4{192, 168, 0, 1})
handle1 == handle2 // true — same canonical handle, single underlying allocation
handle1.Value()    // IP4{192, 168, 0, 1}
```

Use when you have many equal values that you want to compare by identity rather than deep-compare (string interning, IP normalization, label canonicalization).

## `comparable` and interface gotcha

```go
func Distinct[T comparable](xs []T) []T { /* ... */ }

// Go 1.20+ loosened the rule — interface types now satisfy `comparable`:
Distinct([]any{1, "a", []int{1}})
// Compiles, but panics at runtime: `[]int` isn't comparable, and the
// interface dispatch tries to compare it.
```

If you use `comparable` with interface-typed arguments, **the runtime panics** when an actual value's dynamic type isn't comparable (slices, maps, functions). Constrain more tightly when possible.

## Anti-patterns

- **`interface{}` in new code.** Use `any`.
- **Producer-side interfaces with "I" prefix.** Define at the consumer.
- **One-method interface with one implementation.** Premature abstraction.
- **Generic-everything.** If only one type uses it, drop the type parameter.
- **Returning `iter.Seq[T]` then immediately `slices.Collect`-ing on every call.** Just return a slice.
- **Embedding for casual code sharing.** Makes the API surface harder to reason about.
- **Embedded `sync.Mutex` in an exported struct.** Callers copy → broken lock.
- **`v.(T)` panicking type assertion outside "should panic" sites.** Use `v, ok := i.(T)`.
- **Stutter**: `user.UserService` reads worse than `user.Service`.
- **Generic type aliases used to "create a new type."** They're aliases — for distinctness, use a named type.
- **`comparable` with interface-typed values** without verifying the dynamic type is comparable. Runtime panic risk.
- **Returning concrete types via interface variables when callers wanted the concrete API.** Don't lose useful methods to over-abstraction.
