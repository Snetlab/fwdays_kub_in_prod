# Module 02 — Security & Policy as Code

The lab k3s cluster has four namespaces: `mentor`, `student01`, `student02`, and `student03`. A Bash script generates a separate kubeconfig with a short-lived token for each identity.

- The mentor has read and write access to all three student namespaces.
- `student01` and `student03` have read and write access to their own namespaces.
- `student02` has read-only access to `student01` and `default`. None of the four identities has cluster-admin privileges.

Kyverno checks `readOnlyRootFilesystem` in Audit mode. A second policy sets `person=mentor` or `person=student` in the designated namespaces and removes the label elsewhere. The chart's standard exclusions apply to Kyverno controller Pods.

