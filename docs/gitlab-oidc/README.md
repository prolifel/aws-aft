# GitLab OIDC ingress

AWS fetches the OIDC discovery document and JWKS at assume-role time, so only
two paths need to be public: `/.well-known/*` and `/oauth/discovery/keys`.
Everything else returns 404.

## Setup

1. DNS: point `gitlab.example.com` at Cloudflare; tunnel through the
   `cloudflared` config in this directory. Adjust the `gitlab.example.com`
   hostname and the `<TUNNEL_ID>` placeholder.
2. Nginx Proxy Manager: create a proxy host `gitlab.example.com` with the two
   custom locations from `nginx-proxy-manager.conf` (or import the conf
   directly). Enable websockets. Keep "Block common exploits" off — the
   tunnel already path-filters, and the exploit rules can break OIDC JSON
   responses. Internally, GitLab listens on plain HTTP at `gitlab:80`.
3. GitLab (`gitlab.rb`): set `external_url 'https://gitlab.example.com'` so
   the discovery document advertises the public issuer and `jwks_uri`.
   Reconfigure: `sudo gitlab-ctl reconfigure`.
4. Verify:

   `curl -fsS https://gitlab.example.com/.well-known/openid-configuration`
   `curl -fsS https://gitlab.example.com/oauth/discovery/keys`

   Both return GitLab JSON. Any other path must return 404.

## Thumbprint fallback

`modules/ci` leaves `thumbprint_list` empty so AWS auto-fetches the cert.
If AWS rejects the provider (rare with Cloudflare's public CA), capture the
SHA-1 thumbprint and pass it as `oidc_thumbprint`:

```sh
echo | openssl s_client -connect gitlab.example.com:443 -servername gitlab.example.com 2>/dev/null |
  openssl x509 -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f'
```
