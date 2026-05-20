# Supply chain — signing, SBOM, provenance, scanning, admission

The modern container supply chain treats every image as data with provenance: the image itself, an SBOM listing what's in it, a SLSA provenance attestation describing how it was built, and one or more signatures binding all of those to a verifiable identity. Build emits the artifacts; the cluster verifies them at admission. **Notary v1 / Docker Content Trust is dead.** The 2026 stack is Sigstore (cosign + Fulcio + Rekor) for signing, BuildKit-native attestations for SBOM + provenance, Trivy or Grype for vulnerability scanning, and Kyverno's `verifyImages` rule for admission enforcement.

## The four artifacts

| Artifact | What | How produced | How consumed |
|---|---|---|---|
| **Image** | The OCI image itself | `docker buildx build` | `docker pull` / Kubernetes |
| **SBOM** | Software bill of materials (SPDX or CycloneDX) | `--attest type=sbom` at build time, or `syft` post-hoc | Vulnerability scanners; compliance reports |
| **Provenance** | SLSA in-toto attestation describing the build (source, builder, commands) | `--attest type=provenance,mode=max` | Admission policy; auditors |
| **Signature** | Cryptographic proof of who pushed this digest | `cosign sign` | Admission policy at pull time |

All four are addressable by digest, attached to the image index via OCI referrers (image-spec 1.1), and survive pushes across registries.

## Signing — Cosign keyless

Notary v1 / DCT required managing long-lived signing keys, which most teams handled badly. Cosign keyless flips the model: a short-lived (~10 min) X.509 cert from Fulcio, bound to an OIDC identity (GitHub Actions token, Google account, Buildkite agent), signs the image; the signature plus the cert's transparency-log entry go to Rekor. No keys to rotate, no HSMs, no PEM files in CI secrets.

```bash
# Sign — in a CI job with id-token: write permissions
cosign sign --yes ghcr.io/acme/api@sha256:abc...

# Verify
cosign verify \
  --certificate-identity-regexp "^https://github\.com/acme/api/\.github/workflows/build\.yml@" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/acme/api@sha256:abc...
```

Critical: verify against the **identity** (the workflow that ran the build) and the **OIDC issuer** (GitHub's token endpoint). Verifying only "is signed" is meaningless — anyone can sign anything; what matters is that *the workflow you trust* signed it.

GitHub Actions setup:

```yaml
permissions:
  id-token: write              # required for keyless OIDC
  packages: write
  contents: read

steps:
  - uses: sigstore/cosign-installer@v3
  - run: cosign sign --yes ghcr.io/acme/api@${DIGEST}
```

Always sign by **digest**, never tag — tags are mutable, digests are not. A signature on a tag is a signature on whatever the tag pointed at the moment cosign ran, which is not what you want.

## Attestations — SBOM and provenance

BuildKit emits both natively via `--attest`:

```bash
docker buildx build \
  --attest type=sbom \
  --attest type=provenance,mode=max \
  --tag ghcr.io/acme/api:v1.2.3 \
  --push \
  .
```

- **`type=sbom`** — runs `syft` inside BuildKit, produces an SPDX SBOM, attaches it as a referrer.
- **`type=provenance,mode=max`** — SLSA v1 in-toto predicate with full build metadata (source repo, commit SHA, build commands, builder identity, materials). `mode=min` is on by **default** in modern buildx and only includes a minimal subset — disable entirely with `BUILDX_NO_DEFAULT_ATTESTATIONS=1` if you need to.

Inspect:

```bash
docker buildx imagetools inspect --format '{{ json .SBOM }}'        ghcr.io/acme/api:v1.2.3
docker buildx imagetools inspect --format '{{ json .Provenance }}' ghcr.io/acme/api:v1.2.3
```

The attestations are OCI referrers — they live in the registry alongside the image, addressable by the image's digest. `cosign download attestation` and `cosign verify-attestation` work against them once signed.

## SLSA levels — realistic targets

| Level | Means | Realistic? |
|---|---|---|
| **SLSA L1** | Build process produces provenance | Trivial — `--attest provenance` is enough |
| **SLSA L2** | Hosted CI, signed provenance, source version-controlled | **Achievable today** with GitHub Actions + Sigstore. Target this. |
| **SLSA L3** | Hardened/isolated builder, non-falsifiable provenance | Real work — requires builder isolation, controlled environment, signed provenance from a trusted-launch identity |
| **SLSA L4** | Two-party review, hermetic, reproducible | Aspirational for most teams |

Don't claim L3 unless you've done the work — hermetic builders, isolated runners, reviewed build configs. Most "L3-compatible" claims in vendor docs are L2 plus marketing.

## Vulnerability scanning — pick one

Three options, broadly equivalent on coverage but different in shape:

| Scanner | Strengths | Weaknesses |
|---|---|---|
| **Trivy** (Aqua) | Broadest coverage (images, filesystems, repos, K8s, IaC, secrets, licenses), biggest community, reads BuildKit-attached SBOMs natively | Verify releases by digest after the March 2026 supply-chain incident |
| **Grype** (Anchore) | Fastest, cleanest SARIF output, best offline story | Narrower scope (images + filesystems only) |
| **Docker Scout** | Docker-native, integrates with Hub + Desktop, good base-image upgrade recommendations | Best for the dev UX, less common as a CI gate |

**Run one in CI.** Two scanners doesn't make you safer — it makes the pipeline slower and gives you two sets of false positives to triage. Pick by team preference and stick with it.

CI gate example (Trivy → SARIF → GitHub code-scanning):

```yaml
- name: Trivy scan
  uses: aquasecurity/trivy-action@v0.x
  with:
    image-ref: ghcr.io/acme/api:${{ github.sha }}
    format: sarif
    output: trivy.sarif
    severity: HIGH,CRITICAL
    exit-code: 1            # fail the build on findings
    ignore-unfixed: true    # ignore CVEs with no upstream fix

- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: trivy.sarif
```

`ignore-unfixed: true` is the right default — failing on unfixable CVEs just demoralises the team. Re-scan periodically (scheduled job) to catch newly-disclosed CVEs in already-deployed images.

**Docker Scout** is the dev-loop scanner — `docker scout cves <image>`, `docker scout recommendations <image>` to find better base images. Don't replace CI gating with it; complement.

## Admission — Kyverno `verifyImages`

The cluster-side enforcer. Kyverno bundles the Cosign Go library, so `verifyImages` policies validate signatures directly without a separate webhook (Connaisseur's whole architecture is now obsolete).

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-acme-images
spec:
  validationFailureAction: Enforce
  webhookTimeoutSeconds: 30
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds: [Pod]
      verifyImages:
        - imageReferences:
            - "ghcr.io/acme/*"
          mutateDigest: true            # rewrite tag → digest in the admitted Pod
          required: true
          attestors:
            - entries:
                - keyless:
                    issuer: "https://token.actions.githubusercontent.com"
                    subject: "https://github.com/acme/*/.github/workflows/build.yml@refs/heads/main"
                    rekor:
                      url: https://rekor.sigstore.dev
```

`mutateDigest: true` rewrites `image: ghcr.io/acme/api:v1.2.3` to `image: ghcr.io/acme/api@sha256:abc...` in the admitted Pod — so subsequent kubelet pulls hit the immutable digest, not a mutable tag that could be re-pushed.

For provenance/SBOM enforcement, layer on `verifyImages.attestations:` rules that require specific predicate types and identity bindings.

Sigstore's own **policy-controller** is an alternative; pick Kyverno if you're already running it (most teams), policy-controller for Sigstore-only deployments.

## Registry hygiene

The image is only as trustworthy as where it's stored and how it's referenced.

| Practice | What |
|---|---|
| **Digest-pin in manifests** | `image@sha256:...` in Kubernetes/Compose. Tags are mutable — digests are not. Let Renovate/Dependabot bump them. |
| **Authenticate Hub pulls** | Anonymous Docker Hub gives 100 pulls / 6h; authenticated 200. Either authenticate or use a pull-through cache. |
| **Pull-through cache** | ECR pull-through, Harbor proxy cache, `mirror.gcr.io` — eliminates Hub rate limits at the cluster level. |
| **Immutable tags** | Push `:v1.2.3` once, never re-tag. `:latest` is a developer convenience, never a production reference. |
| **Air-gapped / regulated** | Harbor (self-hosted) with Trivy + Cosign + replication. The canonical compliant stack. |
| **OCI artifacts in one place** | Helm charts, SBOMs, Cosign sigs, AI models — all OCI artifacts. One registry per env, not three. |

## Registries — what to pick

| Registry | Strength | Use |
|---|---|---|
| **GHCR** | Free for public, integrated with GitHub OIDC for keyless signing, generous limits | OSS, GitHub-native orgs |
| **ECR** | AWS-native, IAM-integrated, pull-through cache, replication | AWS workloads |
| **Artifact Registry** | GCP-native, integrated with Workload Identity | GCP workloads |
| **Harbor** | Self-hosted, RBAC, Trivy built in, replication | On-prem, air-gapped, multi-cloud |
| **Docker Hub** | Public discoverability | Public OSS releases; **not for CI pulls without auth + caching** |

## The end-to-end pipeline

```
┌──────────┐  buildx        ┌────────┐  cosign       ┌─────────┐  k8s pull    ┌──────────┐
│ source   │  + bake        │ image  │  sign         │ signed  │  + verify   │ admitted │
│ repo     │ ─────────────► │ + SBOM │ ────────────► │ image   │ ──────────► │ Pod      │
│          │  + attest      │ + prov.│  by digest    │         │  via        │          │
└──────────┘                └────────┘               └─────────┘  Kyverno    └──────────┘
                              ▲                        ▲              ▲
                              │                        │              │
                            BuildKit                Sigstore        Kyverno
                            attestations            (Fulcio +      verifyImages
                            (sbom + prov)           Rekor)          rule
```

Each step verifies the previous step's output. The chain breaks if any link is missing — unsigned images bypass admission, unscanned images ship CVEs, missing provenance means you can't audit how the image was built.

## What this looks like in CI

The minimum-viable pipeline:

1. **Build** with attestations: `docker buildx bake --push` + `--attest type=sbom --attest type=provenance,mode=max`.
2. **Scan**: one scanner (Trivy or Grype) gating the PR via SARIF.
3. **Sign** by digest: `cosign sign --yes <ref>@<digest>` with GHA OIDC.
4. **Promote**: `docker buildx imagetools create` to re-tag through environments (no rebuild).
5. **Verify at admission**: Kyverno `verifyImages` rule with identity-bound attestors.

Anything less and the chain has gaps. Anything more is usually optimisation, not security.

## Don't / Do — supply chain

| Don't | Do |
|---|---|
| Notary v1 / Docker Content Trust | Cosign keyless via Sigstore |
| Long-lived signing keys in CI secrets | OIDC-bound short-lived certs from Fulcio |
| Sign by tag | Sign by digest |
| Verify only "is signed" | Verify identity (workflow path) + issuer (OIDC endpoint) |
| Skip `type=provenance` because "the default is fine" | `--attest type=provenance,mode=max` — the default `mode=min` is nearly empty |
| Two or three scanners in CI | One scanner. Pick by team preference. |
| Block PRs on unfixable CVEs | `ignore-unfixed: true` + scheduled rescans |
| `latest` tag in production manifests | Digest pin (`image@sha256:...`) |
| Anonymous Docker Hub pulls in CI | Authenticate, or pull-through cache |
| Connaisseur for admission | Kyverno `verifyImages` (bundles cosign) |
| Trust unsigned upstream images | Mirror through Harbor, sign on ingest, verify on pull |
| Hand-roll an SBOM with `dpkg -l` | `--attest type=sbom` in buildx — emits SPDX automatically |
| Claim SLSA L3 because the CI is "hardened" | Target L2 honestly; document the gap to L3 |
| Re-sign after every re-tag | Re-tag with `imagetools create` (manifest-only) — signature still binds to the digest |
| Suspend a Kyverno verify policy "to ship fast" | Fix the signature; never bypass admission in prod |
