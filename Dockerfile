FROM kong:2.5.1-alpine

USER root
RUN luarocks install kong-plugin-oauth2-audience
USER kong

