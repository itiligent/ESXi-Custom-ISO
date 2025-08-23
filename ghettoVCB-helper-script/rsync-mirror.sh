#!/bin/sh
# mirror dirs: rsync source dest  (dont get source and dest around the wrong way with --delete!)
rsync -avurP --delete --progress /mnt/sdb1/music/CD_Library /mnt/sdc1/
