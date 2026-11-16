S := scripts/nixos-azure
MODE ?= --remote   # or --local

.PHONY: all build upload publish test cleanup prune gallery-init check lock
all:          ; $(S) all $(MODE)
build:        ; $(S) build $(MODE)
upload:       ; $(S) upload $(VERSION)
publish:      ; $(S) publish $(VERSION)
test:         ; $(S) test $(VERSION)
cleanup:      ; $(S) cleanup
prune:        ; $(S) prune $(KEEP)
gallery-init: ; $(S) gallery-init
check:        ; nix flake check --no-build && nix eval --raw .#nixosConfigurations.azure-arm.config.system.nixos.label && echo
lock:         ; nix flake update
