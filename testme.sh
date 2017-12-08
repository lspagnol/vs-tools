#!/bin/bash

function cleanup () {
    if [ -n "$tmpdir" -a -d "$tmpdir" ]; then
	rm -rf "$tmpdir"
    fi
}

trap 'cleanup' EXIT
trap 'exit 4' SIGTERM

cmddir=`dirname $0`
cmdname=`basename $0`
tmpdir=`mktemp -d /tmp/$cmdname.XXXXXX`


eR='\e[31m';eG='\e[32m';eY='\e[33m';eB='\e[34m';eN='\e[0m'

function eecho () {
    C=$1; shift
    echo -e "$C$*$eN"
}

function ececho () {
    rc=$1; shift
    id=$1; shift
    if [ $rc -eq 0 ]; then
        eecho $eG "$id succeeded."
    else
        eecho $eR "$id failed."
    fi   
}

function vlc () {
    [ $verbose -gt $1 ]
    return $?
}
    

function eexec () {
    local id=`printf "[%3.3s]#" $1`; shift
    local eret=$1; shift
    vlc 0 && eecho $eB "$id $*" 
    if vlc 1; then
    	eval $*
    else   
    	eval $* >/dev/null 2>&1
    fi
    local ret=$?
    [ -n "$eret" -a "$eret" -ne 0 ] \
    	&& ret=$(( ret - eret ))
    ececho $ret $id
    return $ret
}

function iwhich () {
    local dpath=`type -p $1`
    echo "$dpath"
    [ -n "$dpath" ]
}

export -f iwhich

function trigger () {
    local id="$1"; shift
    eexec "L$id" 0 "chcontext $SID 456$id bash -c $@"	
    [ -z "$DYC" ] && eexec "D$id" 0 "chcontext bash -c $@"	
}


verbose=0
while getopts ":hdqvA:L" option; do
  case $option in
    h)  # help
    	cat << EOF
Usage: $cmdname [OPTION]... 

  -h        help
  -d        describe VCI flags
  -q        quick test
  -v	    be verbose
  -A [ARCH] architecture specific tests
  -L        limit tests (triggers)

examples:
  
  $cmdname -q	    # quick test
  $cmdname -v 	    # verbose test
  $cmdname -d 	    # list kernel VCI
  
EOF
    	exit 0
    	;;
    d)  # describe VCI
	dvci=1
    	;;
    q)  # just do quick tests
	quick=1
    	;;
    v)  # be verbose 
	verbose=$(( verbose + 1 ))
    	;;
    A)  # architecture specific
	arch="$OPTARG"
    	;;
    L)  # limit tests (triggers)
	ltrig=1
    	;;
  esac
done
shift $(($OPTIND - 1))

eecho $eY "Linux-VServer Test [V0.17] Copyright (C) 2003-2006 H.Poetzl"

for util in vserver chcontext chbind bash; do
    if [ -z `iwhich $util` ]; then
	eecho $eR "utility '$util' could not be found."
	exit 1	
    fi
done

KERN=`uname -srvm`
VSRV=`iwhich vserver 2>/dev/null`

if [ -n "$VSRV" ]; then
    VDIR=`dirname $VSRV`;
else
    if [ -d /usr/lib/util-vserver ]; then
    	VDIR="/usr/lib/util-vserver"
    else
    	VDIR="/usr/lib/vserver"
    fi
fi

grep -q TELL_UNSAFE_CHROOT `iwhich chcontext`
rc1=$?
grep -q util-vserver `iwhich chcontext`
rc2=$?

[ $rc1 -eq 0 -o $rc2 -eq 0 ] && TYPE="E" || TYPE="J"

if chcontext --xid 1 -- true >/dev/null 2>&1; then
    SID="--xid";
else
    SID="--ctx";
fi

if chcontext -- true >/dev/null 2>&1; then 
    DYC=""; DYN=""; 
elif chcontext true >/dev/null 2>&1; then
    DYC=""; DYN=""; TYPE="Jo"
else
    DYC="$SID 49151";
    DYN="--nid 49151";
fi

echo -en $eR
out=`chcontext $SID 1 grep -Ee '[[]|s_context|VxID' /proc/self/status`
rc=$?
if [ $rc -eq 0 ]; then 
    echo -en $eG
    echo "chcontext is working."
    vlc 1 && echo $out | grep -v '^$'
else
    echo "chcontext failed!" 
    echo $out | grep -v '^$'
    chc_fail=1
fi
echo -en $eN

echo -en $eR
out=`chbind $DYN --ip 127.0.0.1 grep 'ipv4' /proc/self/status`
rc=$?
if [ $rc -ne 0 ]; then
    out=`chbind $DYN --ip 127.0.0.1 grep 'V4Root\[0\]:' /proc/self/ninfo`
    rc=$?
fi

if [ $rc -eq 0 ]; then 
    echo -en $eG
    echo "chbind is working." 
    vlc 1 && echo $out | grep -v '^$'
else
    echo "chbind failed!" 
    echo $out | grep -v '^$'
    chb_fail=1
fi
echo -en $eN
vlc 1 && echo $out

CHCV=`chcontext --version 2>&1`
if [ $? -eq 0 ]; then
    TYPE="Ea";
fi
CHBV=`chbind --version 2>&1`
    
CHCO=`echo -e "$CHCV" | 
    sed -n '/--\|version/ {s/.*\ \([0-9][0-9.]*\).*/\1/g;p;q;}'`
CHBI=`echo -e "$CHBV" | 
    sed -n '/--\|version/ {s/.*\ \([0-9][0-9.]*\).*/\1/g;p;q;}'`
vlc 0 && echo -e "$CHCV"

KTNT=`cat /proc/sys/kernel/tainted 2>/dev/null`
[ $KTNT -ne 0 ] && KINF="${KINF}Kt"

INFO=(`sed 's/.*:\t//' /proc/virtual/info 2>/dev/null || echo '<none>'`)
VSRI=`vserver-info - SYSINFO 2>/dev/null || echo ''`

echo "$VSRI" | grep -q 'dietlibc: yes' && UINF="${UINF}D"
APIS=`echo "$VSRI" | sed -n '/APIs/ {s/.*: //;p;q;}'`
SYSC=(`echo "$VSRI" | sed -n '/syscall/ {s/.*: //;p;}'`)

KCIN="$[ 16#${INFO[2]} ]";

KCnodyn=$[ (KCIN >> 0) & 1 ];
KClgacy=$[ (KCIN >> 1) & 1 ];
KClgnet=$[ (KCIN >> 2) & 1 ];
KCngnet=$[ (KCIN >> 3) & 1 ];
KCprocs=$[ (KCIN >> 4) & 1 ];
KCshard=$[ (KCIN >> 5) & 1 ];
KClidle=$[ (KCIN >> 6) & 1 ];
KCsidle=$[ (KCIN >> 7) & 1 ];
KCcowlb=$[ (KCIN >> 8) & 3 ];
KCspace=$[ (KCIN >> 10) & 1 ];
KClvers=$[ (KCIN >> 15) & 1 ];
KCdebug=$[ (KCIN >> 16) & 1 ];
KChstry=$[ (KCIN >> 20) & 1 ];
KCctagm=$[ (KCIN >> 24) & 7 ];

case $KCctagm in
    0) KINF="${KINF}Tn"; Tdesc="${eB}None${eN}" ;;
    1) KINF="${KINF}Tu"; Tdesc="${eG}UID16${eN}" ;;
    2) KINF="${KINF}Tg"; Tdesc="${eG}GID16${eN}" ;;
    3) KINF="${KINF}Tb"; Tdesc="${eG}ID24${eN}" ;;
    4) KINF="${KINF}Ti"; Tdesc="${eY}Internal${eN}" ;;
    5) KINF="${KINF}Tr"; Tdesc="${eY}Runtime${eN}" ;;
    *) KINF="${KINF}T*"; Tdesc="${eR}Unknown${eN}" ;;
esac

[ $KClgacy -ne 0 ] && KINF="${KINF}Lg"
[ $KClgnet -ne 0 ] && KINF="${KINF}n"
[ $KClvers -ne 0 ] && KINF="${KINF}v"
[ $KCnodyn -ne 0 ] && KINF="${KINF}s"
[ $KCngnet -ne 0 ] && KINF="${KINF}N"
[ $KCprocs -ne 0 ] && KINF="${KINF}P"

[ $KCshard -ne 0 ] && KINF="${KINF}H"
[ $KCsidle -ne 0 ] && KINF="${KINF}I"
[ $KClidle -ne 0 ] && KINF="${KINF}i"

[ $KCcowlb -eq 1 ] && KINF="${KINF}w"
[ $KCcowlb -eq 3 ] && KINF="${KINF}W"

[ $KCdebug -ne 0 ] && KINF="${KINF}D"

case ${SYSC[0]} in
    alternative) UINF="${UINF}Sa" ;;
    traditional) UINF="${UINF}St" ;;
    glibc)	 UINF="${UINF}Sg" ;;
    *)		 UINF="${UINF}S*" ;;
esac


echo "$KERN"
echo "$TYPE $CHCO ${SYSC[1]} ($UINF) <$APIS>"
echo "VCI:" ${INFO[*]} "($KINF)"

vlc 0 && sed 's/^[^(]*\((.*)\)\(.*\)$/\1\2/; s/) /)\n/g' /proc/version
echo "---"

if [ -n "$dvci" ]; then
    NDE=( "${eY}disabled${eN}" "${eG}enabled${eN}" )
    NED=( "${eG}enabled${eN}" "${eY}disabled${eN}" )
    PDE=( "${eG}disabled${eN}" "${eY}enabled${eN}" )
    PED=( "${eY}enabled${eN}" "${eG}disabled${eN}" )
    SEC=( "${eY}insecure${eN}" "${eG}secure${eN}" )
    LIM=( "${eG}unlimited${eN}" "${eY}limited${eN}" )
    SKP=( "${eY}not skipped${eN}" "${eG}skipped${eN}" )
    COW=( "${eY}not${eN}" "${eG}partially${eN}" "" "${eG}fully${eN}" )
    LVS=( "${eG}not used${eN}" "${eY}used${eN}" )

    echo -e "[ 0] dynamic contexts are ${PED[$KCnodyn]}."
    echo -e "[ 1] legacy support is ${PDE[$KClgacy]}."
    echo -e "[ 2] legacy network support is ${PDE[$KClgnet]}."
    echo -e "[ 3] ngen networking is ${NDE[$KCngnet]}."
    echo -e "[ 4] procfs is ${SEC[$KCprocs]} by default."
    echo -e "[ 5] the hard scheduler is ${NDE[$KCshard]}."
    echo -e "[ 6] the idle task is ${LIM[$KClidle]}."
    echo -e "[ 7] idle time is ${SKP[$KCsidle]}."

    echo -e "[ 8] cow link breaking is ${COW[$KCcowlb]} supported."
    echo -e "[10] name spaces are ${NDE[$KCspace]}."

    echo -e "[15] legacy version id is ${LVS[$KClvers]}."
    echo -e "[16] vserver debugging is ${PDE[$KCdebug]}."
    echo -e "[17] history tracing is ${PDE[$KChstry]}."

    echo -e "[24] persistent tagging used is $Tdesc."
    echo "---"
fi

if [ -n "$quick" -o -n "$chb_fail" -o -n "$chc_fail" ]; then
    [ -z "$chb_fail" -a -z "$chc_fail" ] && exit 0
    [ -n "$chb_fail" -a -n "$chc_fail" ] && exit 3
    [ -n "$chb_fail" ] && exit 2
    exit 1
fi

UXID=45678

eexec 000   0 "chcontext $DYC true && chcontext $SID $UXID true"
eexec 001   0 "chcontext $SID $UXID egrep 'context|VxID' /proc/self/status"
eexec 011   1 "chcontext --secure $SID $UXID mknod $tmpdir/node c 0 0"
eexec 031   0 "chcontext $DYC --hostname zaphod.$$ uname -a | grep -q zaphod.$$"

eexec 101   0 "chbind $DYN --ip 192.168.0.42 true"
eexec 102   0 "chbind $DYN --ip 192.168.0.1/255.255.255.0 --ip 10.0.0.1/24 true"

eexec 201   0 "chcontext $SID $UXID --flag fakeinit bash -c 'test \$\$ -eq 1'"
eexec 202   0 "chcontext $DYC --flag fakeinit bash -c 'test \$\$ -eq 1'"

if [ -n "$ltrig" ]; then
    echo "---"
    trigger 01 "'true &'"
    trigger 02 "'true | true'"
    trigger 03 "'true & true'"
    trigger 11 "'true >/dev/null'" "</dev/zero"
    trigger 12 "'true </dev/zero'" ">/dev/null"
    trigger 21 "'bash -c \"true &\"&'"
    trigger 22 "'bash -c \"false | true &\"&'"
    trigger 31 "'echo \`ls\`'"
fi

exit 0
