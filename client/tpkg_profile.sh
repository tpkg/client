tpkgbase="/home/t"

if [ -f /etc/tpkg.conf ]
then
  base=`cat /etc/tpkg.conf | grep '^base\s*=' | awk -F= '{print $2}'`
  if [ "$base" != "" ]
  then
    tpkgbase=base
  fi
fi

if [ -f $HOME/.tpkg.conf ]
then
  base=`cat $HOME/.tpkg.conf | grep '^base\s*=' | awk -F= '{print $2}'`
  if [ "$base" != "" ]
  then
    tpkgbase=base
  fi
fi

for i in $tpkgbase/etc/profile.d/*.sh ; do
    if [ -r "$i" ]; then
        . $i
    fi
done
