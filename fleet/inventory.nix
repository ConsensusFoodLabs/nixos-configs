# Fleet inventory — the source of truth for who exists and what they hold.
#
# Plain data, no module logic. Everything derives from this file: accounts,
# administrator rights, home-manager wiring, and which nixosConfigurations
# exist at all (docs/decisions.md D3, D13).
#
# Tight review applies here. In particular `admin` grants root: it is set in
# this file, never in a developer's own file (D12).
#
# No hardware serial numbers. Those live in the private asset register, joined
# to this repository by hostname (D13).
#
# sshKeys are PUBLIC keys. Public keys are not secret and belong in a public
# repository; they are what lets an administrator reach the shared `admin`
# account on any machine (D32). The matching private keys are held by each
# administrator and exist nowhere here.
{
  people = {
    oleg = {
      fullName = "Oleg Mingalev";
      email = "oleg@consensusfoods.com";
      admin = true;
      active = true;
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILeHE4zujO3NvY/N8kVjXE2BigvMuWdfHHtOb6n2dPDI oleg@consensusfoods.com fleet admin"
      ];
    };
  };

  devices = {
    # hostname = { model; assignedTo; profile; }
    "x1c-oleg" = {
      model = "thinkpad-x1c-gen14";
      assignedTo = "oleg";
      profile = "engineering";
    };
  };
}
