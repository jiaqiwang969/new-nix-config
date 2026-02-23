# 极简 NixOS / Darwin 部署 Makefile
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ORB_NIXCONFIG := /mnt/mac$(MAKEFILE_DIR)

ORB_ATTIC_KEY := main:79VGDHuDHe5ct6x6FhBKpRoUL6ybL9D8XedX+7XfDis=

# =========================================================================
# 1. 部署本机 Mac (M4)
# =========================================================================
macbook-pro-m4:
	NIXPKGS_ALLOW_UNFREE=1 nix build --impure --extra-experimental-features nix-command --extra-experimental-features flakes ".#darwinConfigurations.macbook-pro-m4.system"
	sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --impure --flake "$$(pwd)#macbook-pro-m4"

# =========================================================================
# 2. 部署并更新本地 Cache 节点 (nixos-dev)
# =========================================================================
orb-cache:
	orb create nixos:unstable nixos-dev || true
	$(MAKE) _switch_orb_node NAME=nixos-dev
	@echo "Initializing Attic cache server on nixos-dev..."
	@orb -m nixos-dev -u root bash -c '\
		if [ ! -f /var/lib/atticd/env ]; then \
			mkdir -p /var/lib/atticd && \
			echo ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=$$(openssl rand -hex 64) > /var/lib/atticd/env && \
			chmod 600 /var/lib/atticd/env && \
			systemctl restart atticd && \
			sleep 3; \
		fi && \
		TOKEN=$$(atticd-atticadm make-token --sub admin --validity 10y \
			--pull "*" --push "*" --create-cache "*" --configure-cache "*" \
			--configure-cache-retention "*" --destroy-cache "*") && \
		attic login local http://localhost:8080 $$TOKEN && \
		(attic cache create main 2>/dev/null || true) && \
		attic cache configure main --public --upstream-cache-key-name ""'
	@echo "Pushing all /nix/store/* paths to Attic cache..."
	@orb -m nixos-dev -u root bash -c 'nix path-info --all | attic push main --stdin'

# =========================================================================
# 3. 部署 Agent 节点 (用法: make orb-agent/01)
# =========================================================================
orb-agent/%:
	orb create nixos:unstable nixos-agent-$* || true
	$(MAKE) _switch_orb_node NAME=nixos-agent-$*

# -------------------------------------------------------------------------
# 内部命令：统一处理 OrbStack 容器的 NixOS 切换
# -------------------------------------------------------------------------
_switch_orb_node:
	@DEV_IP=$$(orb -m nixos-dev bash -c "hostname -I 2>/dev/null" 2>/dev/null | awk '{print $$1}'); \
	if [ -z "$$DEV_IP" ]; then \
		echo "Warning: could not resolve nixos-dev IP, skipping cache."; \
	else \
		echo "Configuring cache to http://$$DEV_IP:8080/main ..."; \
		echo 'CACHE_URL="http://'$$DEV_IP':8080/main"' > .tmp_cache_script.sh; \
		echo 'if ! curl -sf --connect-timeout 3 "$$CACHE_URL/nix-cache-info" > /dev/null; then' >> .tmp_cache_script.sh; \
		echo '  CACHE_ENTRY="$$CACHE_URL https://cache.nixos.org/"' >> .tmp_cache_script.sh; \
		echo 'else' >> .tmp_cache_script.sh; \
		echo '  CACHE_ENTRY="$$CACHE_URL"' >> .tmp_cache_script.sh; \
		echo 'fi' >> .tmp_cache_script.sh; \
		echo 'if ! grep -q "^substituters = $$CACHE_ENTRY$$" /etc/nix/nix.conf 2>/dev/null; then' >> .tmp_cache_script.sh; \
		echo '  rm -f /etc/nix/nix.conf' >> .tmp_cache_script.sh; \
		echo '  cp /etc/static/nix/nix.conf /etc/nix/nix.conf' >> .tmp_cache_script.sh; \
		echo '  sed -i "s|substituters = .*|substituters = $$CACHE_ENTRY|" /etc/nix/nix.conf' >> .tmp_cache_script.sh; \
		echo '  sed -i "s|trusted-public-keys = |trusted-public-keys = $(ORB_ATTIC_KEY) |" /etc/nix/nix.conf' >> .tmp_cache_script.sh; \
		echo '  systemctl restart nix-daemon 2>/dev/null || true' >> .tmp_cache_script.sh; \
		echo 'fi' >> .tmp_cache_script.sh; \
		cat .tmp_cache_script.sh | orb -m $(NAME) -u root bash; \
		rm -f .tmp_cache_script.sh; \
	fi
	orb -m $(NAME) -u root bash -c 'cd $(ORB_NIXCONFIG) && NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --fast --impure --flake ".#$(NAME)"'
