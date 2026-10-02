# gateway (sshpiper) — increment 1: routing validation

Goal: prove the single-port SSH gateway works on this host **before** refactoring devenv/
templates. Stands up sshpiper + one throwaway target and routes `ssh test@host:2200` into it.

## Run

```bash
cd gateway
./setup.sh                 # generates the gateway keypair + .env from your ~/.ssh/id_ed25519.pub
docker compose up -d       # sshpiper on :2200 + a throwaway target, both on devenv-net
```

## Validate

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test@localhost -p 2200 'echo OK; hostname'
```

Success = you land in the **target** container (prints `OK` + the container's hostname). That
exercises the whole chain:

```
you ──(your key, downstream)──▶ sshpiper :2200 ──(gateway key, upstream)──▶ test-target sshd
     verified via the container's sshpiper.authorized_keys label
                                  routed by sshpiper.username=test
```

## Teardown

```bash
docker compose down
```

## What this validates (the 4 unknowns)
- docker-plugin **username→container routing** (via labels)
- **two-leg auth** (your key downstream, gateway key upstream)
- **network reachability** (sshpiper → container over `devenv-net`)
- host-key handling

Once green, the next increment refactors the devenv templates to produce containers shaped like
`test-target` (labels + `devenv-net`, trusting the gateway key), and drops their published SSH port.
