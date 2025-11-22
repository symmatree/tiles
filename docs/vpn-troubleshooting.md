Notes while we work through this:

* Tales is still able to connect to the VPN
* Tiles used to be, lost the ability during a refactor but also was idle for a while so
  it could in theory have been a software thing (but see above, Tales still works).

### Are the secrets different

One possibility is that Tiles has a different config and its being hidden by the secret mechanisms,
or if the secret in 1password didn't match the Github secret that was actually being used in the past.

Tales' working VPN config, with keys removed, as logged from github by double-base64-encoding it:

```
[Interface]
Address = 10.1.0.2/32
DNS = 10.1.0.1

[Peer]
# AllowedIPs = 0.0.0.0/0
# Top-level VLAN in Unifi config plus VPN subnet
AllowedIPs = 10.0.0.0/16,10.1.0.0/24
Endpoint = lhitw.symmatree.com:4443
```

Output from `op read "op://tiles-secrets/github-vpn-config/wireguard-config" | grep -E -v "^.*Key.*$"`

```
[Interface]
Address = 10.1.0.4/32
DNS = 10.1.0.1

[Peer]
AllowedIPs = 10.0.0.0/16,10.1.0.0/24
Endpoint = lhitw.symmatree.com:4443
```

Output from `op read "op://tiles-secrets/github-vpn-client/notesPlain" | grep -E -v "^.*Key.*$"`

```
[Interface]
Address = 10.1.0.4/32
DNS = 10.1.0.1

[Peer]
AllowedIPs = 10.0.0.0/16,10.1.0.0/24
Endpoint = lhitw.symmatree.com:4443
```

Those outputs might differ in whether there's a newline at the end of the file but otherwise
seem identical to me.
