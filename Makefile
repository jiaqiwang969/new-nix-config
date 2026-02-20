# Connectivity info for Linux VM
NIXADDR ?= unset
NIXPORT ?= 22
NIXUSER ?= jqwang

# IP of the Attic cache VM (for /etc/hosts injection before avahi is available)
CACHE_ADDR ?= 192.168.64.13

# Get the path to this Makefile and directory
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# The name of the nixosConfiguration in the flake
NIXNAME ?= vm-aarch64

# Disk device in the VM (sda for x86 SATA, vda for aarch64 virtio)
NIXDISK ?= vda

# SSH options that are used. These aren't meant to be overridden but are
# reused a lot so we just store them up here.
SSH_OPTIONS=-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

# Read the first available public key from common locations and
# inject it during bootstrap0 (so stage 2 can use key auth immediately).
SSH_PUBLIC_KEY_PATH ?=
SSH_PUBLIC_KEY_B64_DECODED := $(shell \
	if [ -n "$(SSH_PUBLIC_KEY_PATH)" ] && [ -f "$(SSH_PUBLIC_KEY_PATH)" ]; then \
		cat "$(SSH_PUBLIC_KEY_PATH)"; \
	elif [ -f "$(HOME)/.ssh/id_ed25519.pub" ]; then \
		cat "$(HOME)/.ssh/id_ed25519.pub"; \
	elif [ -f "$(HOME)/.ssh/id_rsa.pub" ]; then \
		cat "$(HOME)/.ssh/id_rsa.pub"; \
	elif [ -f "$(HOME)/.ssh/id_ecdsa.pub" ]; then \
		cat "$(HOME)/.ssh/id_ecdsa.pub"; \
	elif [ -f "$(HOME)/.ssh/id_ecdsa_sk.pub" ]; then \
		cat "$(HOME)/.ssh/id_ecdsa_sk.pub"; \
	else \
		echo ""; \
	fi)

SSH_PUBLIC_KEY_B64 := $(shell \
	if [ -n "$(SSH_PUBLIC_KEY_PATH)" ] && [ -f "$(SSH_PUBLIC_KEY_PATH)" ]; then \
		cat "$(SSH_PUBLIC_KEY_PATH)"; \
	elif [ -f "$(HOME)/.ssh/id_ed25519.pub" ]; then \
		cat "$(HOME)/.ssh/id_ed25519.pub"; \
	elif [ -f "$(HOME)/.ssh/id_rsa.pub" ]; then \
		cat "$(HOME)/.ssh/id_rsa.pub"; \
	elif [ -f "$(HOME)/.ssh/id_ecdsa.pub" ]; then \
		cat "$(HOME)/.ssh/id_ecdsa.pub"; \
	elif [ -f "$(HOME)/.ssh/id_ecdsa_sk.pub" ]; then \
		cat "$(HOME)/.ssh/id_ecdsa_sk.pub"; \
	else \
		echo ""; \
	fi | base64 | tr -d '\n')

ifneq ($(strip $(SSH_PUBLIC_KEY_B64)),)
BOOTSTRAP0_AUTHKEYS = \
	mkdir -p /mnt/root/.ssh /mnt/home/jqwang/.ssh; \
	echo '$(SSH_PUBLIC_KEY_B64)' | base64 -d > /mnt/root/.ssh/authorized_keys; \
	cp /mnt/root/.ssh/authorized_keys /mnt/home/jqwang/.ssh/authorized_keys; \
	chmod 700 /mnt/root/.ssh /mnt/home/jqwang/.ssh; \
	chmod 600 /mnt/root/.ssh/authorized_keys /mnt/home/jqwang/.ssh/authorized_keys; \
	chown -R 0:0 /mnt/root/.ssh || true; \
	chown -R 1000:100 /mnt/home/jqwang/.ssh || true
endif

# Optional proxy variables for slow networks.
# Example:
#   export https_proxy=http://127.0.0.1:7890
#   export http_proxy=http://127.0.0.1:7890
#   export all_proxy=socks5://127.0.0.1:7890
PROXY_ENV :=
ifneq ($(strip $(http_proxy)),)
PROXY_ENV += http_proxy=$(http_proxy) HTTPS_PROXY=$(http_proxy)
endif
ifneq ($(strip $(https_proxy)),)
PROXY_ENV += https_proxy=$(https_proxy) HTTPS_PROXY=$(https_proxy)
endif
ifneq ($(strip $(all_proxy)),)
PROXY_ENV += all_proxy=$(all_proxy) ALL_PROXY=$(all_proxy)
endif

# We need to do some OS switching below.
UNAME := $(shell uname)

switch:
ifeq ($(UNAME), Darwin)
	$(PROXY_ENV) NIXPKGS_ALLOW_UNFREE=1 nix build --impure --extra-experimental-features nix-command --extra-experimental-features flakes ".#darwinConfigurations.${NIXNAME}.system"
	sudo $(PROXY_ENV) NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --impure --flake "$$(pwd)#${NIXNAME}"
else
	sudo $(PROXY_ENV) NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --impure --flake ".#${NIXNAME}"
endif

test:
ifeq ($(UNAME), Darwin)
	$(PROXY_ENV) NIXPKGS_ALLOW_UNFREE=1 nix build --impure ".#darwinConfigurations.${NIXNAME}.system"
	sudo $(PROXY_ENV) NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild test --impure --flake "$$(pwd)#${NIXNAME}"
else
	sudo $(PROXY_ENV) NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --impure --flake ".#$(NIXNAME)"
endif

# This builds the given NixOS configuration and pushes the results to the
# cache. This does not alter the current running system. This requires
# cachix authentication to be configured out of band.
cache:
	$(PROXY_ENV) nix build '.#nixosConfigurations.$(NIXNAME).config.system.build.toplevel' --json \
		| jq -r '.[].outputs | to_entries[].value' \
		| cachix push mitchellh-nixos-config

# Backup secrets so that we can transer them to new machines via
# sneakernet or other means.
.PHONY: secrets/backup
secrets/backup:
	tar -czvf $(MAKEFILE_DIR)/backup.tar.gz \
		-C $(HOME) \
		--exclude='.gnupg/.#*' \
		--exclude='.gnupg/S.*' \
		--exclude='.gnupg/*.conf' \
		--exclude='.ssh/environment' \
		.ssh/ \
		.gnupg

.PHONY: secrets/restore
secrets/restore:
	if [ ! -f $(MAKEFILE_DIR)/backup.tar.gz ]; then \
		echo "Error: backup.tar.gz not found in $(MAKEFILE_DIR)"; \
		exit 1; \
	fi
	echo "Restoring SSH keys and GPG keyring from backup..."
	mkdir -p $(HOME)/.ssh $(HOME)/.gnupg
	tar -xzvf $(MAKEFILE_DIR)/backup.tar.gz -C $(HOME)
	chmod 700 $(HOME)/.ssh $(HOME)/.gnupg
	chmod 600 $(HOME)/.ssh/* || true
	chmod 700 $(HOME)/.gnupg/* || true

# bootstrap a brand new VM. The VM should have NixOS ISO on the CD drive
# and just set the password of the root user to "root". This will install
# NixOS. After installing NixOS, you must reboot and set the root password
# for the next step.
#
# NOTE(mitchellh): I'm sure there is a way to do this and bootstrap all
# in one step but when I tried to merge them I got errors. One day.
vm/bootstrap0:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) root@$(NIXADDR) " \
		parted /dev/$(NIXDISK) -- mklabel gpt; \
		parted /dev/$(NIXDISK) -- mkpart primary 512MB -8GB; \
		parted /dev/$(NIXDISK) -- mkpart primary linux-swap -8GB 100\%; \
		parted /dev/$(NIXDISK) -- mkpart ESP fat32 1MB 512MB; \
		parted /dev/$(NIXDISK) -- set 3 esp on; \
		sleep 1; \
		mkfs.ext4 -L nixos /dev/$(NIXDISK)1; \
		mkswap -L swap /dev/$(NIXDISK)2; \
		mkfs.fat -F 32 -n boot /dev/$(NIXDISK)3; \
		sleep 1; \
		mount /dev/disk/by-label/nixos /mnt; \
		mkdir -p /mnt/boot; \
		mount /dev/disk/by-label/boot /mnt/boot; \
		nixos-generate-config --root /mnt; \
		sed --in-place '/system\.stateVersion = .*/a \
			nix.package = pkgs.nixVersions.latest;\n \
			nix.extraOptions = \"experimental-features = nix-command flakes\";\n \
			nix.settings.substituters = [\"http://nixos-utm-cache.local:8080/main\" \"https://nix-community.cachix.org\" \"https://jj-vcs.cachix.org\" \"https://mitchellh-nixos-config.cachix.org\"];\n \
			nix.settings.trusted-public-keys = [\"main:oA4xP/b/OGxNldLb2kqO9gSu8Bzdu3mp5RXl4LwZqGA=\" \"nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=\" \"jj-vcs.cachix.org-1:sn2MddHr1ztFndbsGHMHV6xpMGHlHTb0FQGR/UMqybM=\" \"mitchellh-nixos-config.cachix.org-1:bjEbXJyLrL1HZZHBbO4QALnI5faYZppzkU4D2s0G8RQ=\"];\n \
  			services.openssh.enable = true;\n \
			services.openssh.settings.PasswordAuthentication = true;\n \
			services.openssh.settings.PermitRootLogin = \"yes\";\n \
			users.users.root.initialPassword = \"root\";\n \
		' /mnt/etc/nixos/configuration.nix; \
		$(BOOTSTRAP0_AUTHKEYS); \
		nixos-install --no-root-passwd && reboot; \
	"

# after bootstrap0, run this to finalize. After this, do everything else
# in the VM unless secrets change.
vm/bootstrap:
	NIXUSER=root $(MAKE) vm/copy
	NIXUSER=root $(MAKE) vm/switch
	$(MAKE) vm/secrets
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo reboot; \
	"

# copy our secrets into the VM
vm/secrets:
	# GPG keyring (skip if not present)
	@if [ -d "$(HOME)/.gnupg" ]; then \
		rsync -av -e 'ssh $(SSH_OPTIONS)' \
			--exclude='.#*' \
			--exclude='S.*' \
			--exclude='*.conf' \
			$(HOME)/.gnupg/ $(NIXUSER)@$(NIXADDR):~/.gnupg; \
	else \
		echo "Skipping .gnupg (not found)"; \
	fi
	# SSH keys
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='environment' \
		$(HOME)/.ssh/ $(NIXUSER)@$(NIXADDR):~/.ssh

# copy the Nix configurations into the VM.
vm/copy:
	rsync -av -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='vendor/' \
		--exclude='.git/' \
		--exclude='.git-crypt/' \
		--exclude='.jj/' \
		--exclude='iso/' \
		--rsync-path="sudo rsync" \
		$(MAKEFILE_DIR)/ $(NIXUSER)@$(NIXADDR):/nix-config

# run the nixos-rebuild switch command. This does NOT copy files so you
# have to run vm/copy before.
# We pass the Attic cache by IP via --option so it works even before
# avahi/mDNS is available (NixOS /etc/hosts is read-only).
vm/switch:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --impure --flake \"/nix-config#${NIXNAME}\" \
			--option extra-substituters 'http://$(CACHE_ADDR):8080/main' \
			--option extra-trusted-public-keys 'main:oA4xP/b/OGxNldLb2kqO9gSu8Bzdu3mp5RXl4LwZqGA=' \
	"

# Build a WSL installer
.PHONY: wsl
wsl:
	 nix build ".#nixosConfigurations.wsl.config.system.build.installer"

# ---------------------------------------------------------------------------
# Attic binary cache management
# ---------------------------------------------------------------------------

# Initialize Attic on the VM: generate server secret, create cache, make it public.
# Run this once after the first vm/switch that deploys atticd.
# Secret is generated locally (openssl not available on VM) and uses HS256.
.PHONY: cache/init
cache/init:
	@echo "Initializing Attic on $(NIXADDR) ..."
	@SECRET=$$(openssl rand -hex 64) && \
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) bash -c "'\
		if [ ! -f /var/lib/atticd/env ]; then \
			sudo mkdir -p /var/lib/atticd && \
			echo ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=$$SECRET | sudo tee /var/lib/atticd/env > /dev/null && \
			sudo chmod 600 /var/lib/atticd/env && \
			sudo systemctl restart atticd && \
			sleep 3; \
		fi && \
		TOKEN=\$$(sudo atticd-atticadm make-token --sub admin --validity 10y \
			--pull \"*\" --push \"*\" --create-cache \"*\" --configure-cache \"*\" \
			--configure-cache-retention \"*\" --destroy-cache \"*\") && \
		attic login local http://localhost:8080 \$$TOKEN && \
		(attic cache create main 2>/dev/null || true) && \
		attic cache configure main --public --upstream-cache-key-name \"\" && \
		echo --- && \
		echo Attic cache ready. Signing public key: && \
		attic cache info main 2>&1 | grep \"Public Key\" \
	'"

# Push all store paths on the VM to the Attic cache.
.PHONY: cache/push
cache/push:
	@echo "Pushing all store paths to Attic cache ..."
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) bash -c "' \
		nix path-info --all | attic push main --stdin \
	'"

# Test that the local Attic cache is reachable from the host.
.PHONY: cache/test
cache/test:
	@curl -sf http://nixos-utm-cache.local:8080/main/nix-cache-info && echo "Cache is up!" || echo "Cache unreachable."

# Include UTM-specific targets
include Makefile.utm
