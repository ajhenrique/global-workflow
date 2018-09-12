#!/bin/bash
set -x

###############################################################
## CICE5/MOM6 post driver script 
## FHRGRP : forecast hour group to post-process (e.g. 0, 1, 2 ...)
## FHRLST : forecast hourlist to be post-process (e.g. anl, f000, f000_f001_f002, ...)
###############################################################

# Source FV3GFS workflow modules
. $HOMEgfs/ush/load_fv3gfs_modules.sh
status=$?
[[ $status -ne 0 ]] && exit $status

#############################
# Source relevant config files
#############################
configs="base ocnpost"
config_path=${EXPDIR:-$NWROOT/gfs.${gfs_ver}/parm/config}
for config in $configs; do
    . $config_path/config.$config
    status=$?
    [[ $status -ne 0 ]] && exit $status
done


##########################################
# Source machine runtime environment
##########################################
. $HOMEgfs/env/${machine}.env ocnpost
status=$?
[[ $status -ne 0 ]] && exit $status


##############################################
# Obtain unique process id (pid) and make temp directory
##############################################
export job=${job:-"ocnpost"}
export pid=${pid:-$$}
export outid=${outid:-"LL$job"}
export jobid=${jobid:-"${outid}.o${pid}"}

if [ $RUN_ENVIR = "nco" ]; then
    export DATA="$DATAROOT/${job}.${pid}"
else
    export DATAROOT="$RUNDIR/$CDATE/$CDUMP"
    export DATA="$DATAROOT/DATAocnpost$FHRGRP"
fi
[[ -d $DATA ]] && rm -rf $DATA
mkdir -p $DATA
cd $DATA

##############################################
# Run setpdy and initialize PDY variables
##############################################
export cycle="t${cyc}z"
setpdy.sh
. ./PDY

##############################################
# Define the Log File directory
##############################################
export jlogfile=${jlogfile:-$COMROOT/logs/jlogfiles/jlogfile.${job}.${pid}}

##############################################
# Determine Job Output Name on System
##############################################
export pgmout="OUTPUT.${pid}"
export pgmerr=errfile


##############################################
# Set variables used in the exglobal script
##############################################
export CDATE=${CDATE:-${PDY}${cyc}}
export CDUMP=${CDUMP:-${RUN:-"gfs"}}
if [ $RUN_ENVIR = "nco" ]; then
    export ROTDIR=${COMROOT:?}/$NET/$envir
fi

##############################################
# Begin JOB SPECIFIC work
##############################################

if [ $RUN_ENVIR = "nco" ]; then
    export COMIN=${COMIN:-$ROTDIR/$RUN.$PDY/$cyc}
    export COMOUT=${COMOUT:-$ROTDIR/$RUN.$PDY/$cyc}
else
    export COMIN="$ROTDIR/$CDUMP.$PDY/$cyc"
    export COMOUT="$ROTDIR/$CDUMP.$PDY/$cyc"
fi
[[ ! -d $COMOUT ]] && mkdir -m 775 -p $COMOUT

if [ $FHRGRP -eq 0 ]; then
    fhrlst="anl"
else
    fhrlst=$(echo $FHRLST | sed -e 's/_/ /g; s/f/ /g; s/,/ /g')
fi

export OMP_NUM_THREADS=1
export ENSMEM=${ENSMEM:-01}

export IDATE=$CDATE

#---------------------------------------------------------------
echo "PT DEBUG fhrlst is $fhrlst"

FHOUT=$FHOUT_GFS

for fhr in $fhrlst; do

  export fhr=$fhr

  ### EMC_ugcs workflow job - begin
  #  --------------------------------------
  #  cp cice data to COMOUT directory
  #  --------------------------------------

  cd $RUNDIR/$IDATE/$CDUMP/fcst
  echo "PT DEBUG : Where am I?"
  pwd

  YYYY0=`echo $IDATE | cut -c1-4`
  MM0=`echo $IDATE | cut -c5-6`
  DD0=`echo $IDATE | cut -c7-8`
  HH0=`echo $IDATE | cut -c9-10`
  SS0=$((10#$HH0*3600))

  VDATE=$($NDATE $fhr $IDATE)
  YYYY=`echo $VDATE | cut -c1-4`
  MM=`echo $VDATE | cut -c5-6`
  DD=`echo $VDATE | cut -c7-8`
  HH=`echo $VDATE | cut -c9-10`
  SS=$((10#$HH*3600))

  DDATE=$($NDATE -$FHOUT $VDATE)

  if [[ 10#$fhr -eq 0 ]]; then
    $NCP -p history/iceh_ic.${YYYY0}-${MM0}-${DD0}-`printf "%5.5d" ${SS0}`.nc $COMOUT/iceic$VDATE.$ENSMEM.$IDATE.nc
    status=$?
    [[ $status -ne 0 ]] && exit $status
    echo "fhr is 0, only copying ice initial conditions... exiting"
#BL2018
    exit 0 # only copy ice initial conditions.
#BL2018
  else
#BL2018
    $NCP -p history/iceh_`printf "%0.2d" $FHOUT`h.${YYYY}-${MM}-${DD}-`printf "%5.5d" ${SS}`.nc $COMOUT/ice$VDATE.$ENSMEM.$IDATE.nc
#    $NCP -p history/iceh.${YYYY}-${MM}-${DD}.nc $COMOUT/ice$VDATE.$ENSMEM.$IDATE.nc
#BL2018
    status=$?
    [[ $status -ne 0 ]] && exit $status
  fi

  hh_inc_m=$((10#$FHOUT/2))
  hh_inc_o=$((10#$FHOUT  ))

  # ------------------------------------------------------
  #  adjust the dates on the mom filenames and save
  # ------------------------------------------------------

  m_date=$($NDATE $hh_inc_m $DDATE)
  p_date=$($NDATE $hh_inc_o $DDATE)

  #set +x
  # This loop probably isn't needed
  until [ $p_date -gt $VDATE ] ; do
    year=`echo $m_date | cut -c1-4`
    month=`echo $m_date | cut -c5-6`
    day=`echo $m_date | cut -c7-8`
    hh=`echo $m_date | cut -c9-10`

# ocn_2016_10_03_03.nc
# ocn_2016_10_03_09.nc
# ocn_2016_10_03_15.nc
# ocn_2016_10_03_21.nc

    export ocnfile=ocn_${year}_${month}_${day}_${hh}.nc

    year=`echo $p_date | cut -c1-4`
    month=`echo $p_date | cut -c5-6`
    day=`echo $p_date | cut -c7-8`
    hh=`echo $p_date | cut -c9-10`

    echo "cp -p $ocnfile $COMOUT/ocn$p_date.$ENSMEM.$IDATE.nc"
    $NCP -p $ocnfile $COMOUT/ocn$p_date.$ENSMEM.$IDATE.nc
    status=$?
    [[ $status -ne 0 ]] && exit $status

    m_date=$($NDATE $hh_inc_o $m_date)
    p_date=$($NDATE $hh_inc_o $p_date)
  done
  #set -x

  #  --------------------------
  #  make the ocn grib files 
  #  --------------------------

  #  Regrid the MOM6 files
  # The regrid scripts use CDATE for the current day, restore it to IDATE afterwards
  export CDATE=$VDATE

  cd $DATA

  # Regrid the MOM6 and CICE5 output from tripolar to regular grid via NCL
  # This can take .25 degree input and convert to .5 degree - other opts avail

  export MOM6REGRID=$UGCSsrc/post/mom6_regrid
  $MOM6REGRID/run_regrid.sh
  status=$?
  [[ $status -ne 0 ]] && exit $status


  # Convert the .nc files to grib2
  export executable=$MOM6REGRID/exec/reg2grb2.x
  $MOM6REGRID/run_reg2grb2.sh
  status=$?
  [[ $status -ne 0 ]] && exit $status

  $NMV ocnr$CDATE.$ENSMEM.${IDATE}_0p5x0p5_MOM6.grb2 $COMOUT/ocnh$CDATE.$ENSMEM.${IDATE}.grb2
  status=$?
  [[ $status -ne 0 ]] && exit $status

  # Restore CDATE to what is expected
  export CDATE=$IDATE

  # clean up working folder
  rm -Rf $DATA

done

###############################################################
# Exit out cleanly
exit 0
