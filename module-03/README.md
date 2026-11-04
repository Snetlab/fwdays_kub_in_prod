# Module 03 — Platform Engineering

The existing Argo CD instance on the lab k3s cluster has a dedicated project, course-platform, and application, course-kyverno-policies. Both Module 02 Kyverno policies are packaged in one Helm chart. Argo CD automatically syncs the policies from Git and corrects drift in the cluster.

Verification: 
Helm linting, server-side dry runs, and the RBAC and Kyverno regression tests passed. Argo CD reported Synced / Healthy.
