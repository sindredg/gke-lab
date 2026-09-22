# Serves the project page from an image that already runs as non-root.
# Pinned by digest, so a rebuild reproduces the same packages. Dependabot moves the pin.
FROM nginxinc/nginx-unprivileged:1.31.5-alpine@sha256:19c132c9ab02d3b783f478743dafc7a7f42e27aa7d2bdcbec1bb1128ca8f2a07

# The entrypoint runs envsubst on this at startup, which carries Pod facts.
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY index.html /usr/share/nginx/html/index.html

# Sourced before the template is filled in, so RUNTIME_UID exists in time.
COPY 10-runtime-facts.envsh /docker-entrypoint.d/10-runtime-facts.envsh

# Limits envsubst to this project's variables, so nginx's own are left alone.
ENV NGINX_ENVSUBST_FILTER="^(POD_|NODE_|IMAGE_|RUNTIME_)"

# A port below 1024 needs a capability the restricted standard forbids.
EXPOSE 8080

LABEL org.opencontainers.image.title="k8-lab frontend" \
      org.opencontainers.image.source="https://github.com/sindredg/k8-lab"
