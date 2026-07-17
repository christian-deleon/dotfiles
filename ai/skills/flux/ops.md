## Secrets — 1Password Operator + Reflector

The default secrets pattern is 1Password Connect + Operator, **not** SOPS, ESO, or Sealed Secrets:

1. **`infrastructure/base/1password/`** installs the 1Password Connect Helm chart with the operator enabled. The chart pulls credentials from a pre-provisioned `op-credentials` Secret and a token Secret in the `1password` namespace.
2. **App manifests reference 1Password items via `OnePasswordItem` CRDs**. The operator materializes a regular `Secret` with the same name in the same namespace:
   ```yaml
   apiVersion: onepassword.com/v1
   kind: OnePasswordItem
   metadata:
     name: app-db-credentials
     namespace: app
   spec:
     itemPath: "vaults/<vault-uuid>/items/<item-uuid>"
   ```
3. **Cross-namespace replication uses `emberstack/reflector`**. Install via `dependencies/base/reflector/`. Annotate a source Secret to allow reflection, and a target namespace's annotation pulls it in. Common case: the cnpg operator needs DB credentials in the `postgres` namespace, but the consuming app needs them in its own namespace too.

Don't introduce SOPS or ESO into a repo that already uses this pattern. If a new project genuinely needs SOPS, the Flux Kustomization gets a `decryption: { provider: sops, secretRef: { name: sops-age } }` block — but make that an explicit decision, not an accidental drift.

Never commit plaintext `Secret` manifests. The only `Secret`-like things in git are `OnePasswordItem` resources and Reflector reflections.

## Bootstrap

`flux bootstrap` is the only supported install path. It commits the controller manifests + a `flux-system` Kustomization into `clusters/<name>/flux-system/` in your repo, and Flux reconciles itself from there.

- Don't edit `flux-system/gotk-components.yaml` or `gotk-sync.yaml` by hand. Re-run `flux bootstrap` to upgrade or change settings.
- Bootstrap once per cluster; `--path=./flux/clusters/<cluster_name>` keeps clusters isolated.
- Use `--components-extra=image-reflector-controller,image-update-controller` if you want image automation.

## Image automation (optional)

If using image-update-automation, three CRDs work together: `ImageRepository` (scans tags) → `ImagePolicy` (selects one per a strategy: semver, regex, alphabetical) → `ImageUpdateAutomation` (commits the new tag back to git). Annotate the YAML field to update with `# {"$imagepolicy": "ns/policy"}`. The bot writes commits; Flux reconciles them like any other change. If the repo already uses Renovate for version bumps, don't duplicate that with image-automation — pick one.

## Validate before committing

```sh
# Render and validate Kustomize bases
kubectl kustomize ./flux/apps/base/<app> | kubectl apply --dry-run=client -f -

# Validate Flux manifests against the schemas
flux check
flux tree kustomization <name>     # see the resource graph
flux diff kustomization <name> --path ./flux/...  # preview a reconcile vs the cluster
```
