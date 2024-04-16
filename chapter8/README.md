## Notes on cloud init (WIP)

### Scripts executed per boot, and not only at provisioning time

Cloud-init is typically designed for initialization tasks during the instance
first boot process.  It is also a place to add tasks to be executed at the
provisioning phase of the VM, and not tasks to be executed every boot (different
from systemd)—but note you can configure it to do so.

To run scripts for every boot, you can use the `per-boot` folder. If one wants
to use cloud-init to run a given scriptin every boot, add the script in
`/var/lib/cloud/scripts/per-boot`. Scripts in this folder are executed in
alphabetical order. Make sure the script has `#!/bin/sh` in its first line and
proper executable permission such as `chmod 744 script.sh`.


### Re-execute a modified cloud init once VM is provisioned

Some times you may get into a situation that you provisioned a VM with a given
cloud-init, but once you are in the VM you realized you made a mistake in the
cloud-init script. You want to quickly fix it to conclude the testing but you
don't want to reprovision the VM.

Basically what you can do is to modify the `runcmd` script:

```
vi  /var/lib/cloud/instance/scripts/runcmd
```

and run cloud-init for that particular cloud-init step (user script):

```
sudo /usr/bin/cloud-init single -n cc_scripts_user
```

Where

- `single`: This is an argument passed to cloud-init, indicating that it should
  run in single mode. In single mode, cloud-init processes only the specified
  configuration set and then exits. This is useful for debugging or testing
  specific configurations without running the entire initialization process.

- `-n cc_scripts_user:` This is another argument passed to cloud-init,
  specifying the name of the configuration set (cc_scripts_user) to be processed
  in single mode. Configuration sets in cloud-init contain instructions for
  customizing the cloud instance, such as running scripts or setting up users.


## References

- **cloud init:**
  [https://cloudinit.readthedocs.io/en/latest/explanation/boot.html](https://cloudinit.readthedocs.io/en/latest/explanation/boot.html])
- **cloud init per-boot:** [https://cloudinit.readthedocs.io/en/20.4/topics/modules.html?highlight=per-boot#scripts-per-boot](https://cloudinit.readthedocs.io/en/20.4/topics/modules.html?highlight=per-boot#scripts-per-boot)
