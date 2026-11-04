# Module 04 — Service Mesh

Istio 1.31.3 runs in sidecar mode on the lab k3s cluster. Automatic injection is enabled in student01, student02, and student03. Kyverno rejects new Pods labeled person=student if the istio-proxy sidecar or the Istio injection status annotation is missing.

Verification: 
Server-side dry runs confirmed injection in all three student namespaces, no injection in mentor and default, and rejection when a student Pod explicitly disabled injection. A live test Pod in student01 reached Ready with istio-proxy and was then removed.
