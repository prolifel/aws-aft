# Root variables declare only per-account values; org-wide constants live in the root's module call

Per-account OpenTofu roots re-declared the full module variable interface just to pass values through: the bootstrap root mirrored all twenty-six module variables across its variables file and the deployment var-file, and the vending and CI roots carried variables nothing ever fed. The duplication made the roots read as nested copies of their modules and drifted silently when a module interface changed.

Each root now declares only per-account variables (the bootstrap contacts plus the deployment region) and required inputs; org-wide constants are supplied once, either as a literal in the root's module call or by a module default. A deterministic guard test enforces the contract: every root variable must exist in the module it calls (with a root-only allowlist), and module call depth must stay at one. The deployment var-file now carries only per-account contact values; changing a central-account value means editing the literal in the bootstrap root's module call.

Module interfaces, the provisioning scripts, and the CI pipeline are unchanged, so existing consumers keep working. The variable split is captured in the project glossary as per-account variable versus org-wide constant.
