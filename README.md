# eck-glance
Tool to make eck diag a bit more human readable

## Install
git clone https://github.com/jlim0930/eck-glance.git

## Use
Goto the extracted eck-diag and run `/path/eck_1.sh` for most cases.

If your workstation is able to handle it you can run `/path/eck_1fast.sh` it will launch all the jobs in the background and run all the subscripts at once - I tried this on multiple diags and it was super fast !!

All `eck_*_1.sh` scripts will give high level of the `kind` that you are looking at(more detailed than just `kubectl get <kind>`)
All `eck_*_2.sh` will give a more descriptive and detailed view of the resource(its more like `kubectl describe <kind> <resource>`)

If you want to run individual jobs all` eck_*_1.sh`, scripts can be ran with `eck_*_1.sh /path/file.json`
  Example: `/path/eck_beat_1.sh beat.json`

If you want to run individual jobs for all` eck_*_2.sh`, scripts can be ran with `eck_*_2.sh /path/proper.json resourcename`
  Example: `/path/eck_beat_2.sh beat.json filebeat`
  

After the `eck-glance` runs I would start looking at eck_events.txt from the `<namespace>` directory, then eck_pods.txt, etc.. depending on the issue at hand.


TODO

* Find `# FIX` for things to fix.
* Validate code against different diags to ensure proper coverage
* Find ways to remove loops
* Find ways to make current jq queries more simple and account for various nulls
* 
