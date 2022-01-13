#!/bin/bash -e

# NB: -e makes script to fail if internal script fails (for example when --run is enabled)

#######################################
##         CHECK ARGS
#######################################
NARGS="$#"
echo "INFO: NARGS= $NARGS"

if [ "$NARGS" -lt 1 ]; then
	echo "ERROR: Invalid number of arguments...see script usage!"
  echo ""
	echo "**************************"
  echo "***     USAGE          ***"
	echo "**************************"
 	echo "$0 [ARGS]"
	echo ""
	echo "=========================="
	echo "==    ARGUMENT LIST     =="
	echo "=========================="
	echo "*** MANDATORY ARGS ***"
	echo "--inputfile=[FILENAME] - Input FITS file"
	echo ""

	echo "*** OPTIONAL ARGS ***"

	echo "=== AEGEAN OPTIONS ==="
	echo "--bkggrid=[GRID_SIZE] - The [x,y] size of the grid to use [Default = ~4* beam size square]"
	echo "--bkgbox=[BOX_SIZE] - The [x,y] size of the box over which the rms/bkg is calculated [Default = 5*grid]"
	echo "--seedthr=[SEED_THR] - The clipping value (in sigmas) for seeding islands [default: 5]"
	echo "--mergethr=[MERGE_THR] - The clipping value (in sigmas) for growing islands [default: 4]"
	echo "--fit-maxcomponents=[NCOMP] - If more than *maxsummits* summits are detected in an island, no fitting is done, only estimation"
	echo ""

	echo "=== RUN OPTIONS ==="
	echo "--ncores=[NCORES] - Number of cores to use [Default = all available]"
	echo "--run - Run the generated run script on the local shell. If disabled only run script will be generated for later run."	
	echo "--no-logredir - Do not redirect logs to output file in script "
	echo "--jobdir=[PATH] - Directory where to run job (default=/home/[RUNUSER]/aegean-job)"
	echo "--outdir=[OUTPUT_DIR] - Output directory where to put run output file (default=pwd)"
	echo "--waitcopy - Wait a bit after copying output files to output dir (default=no)"
	echo "--copywaittime=[COPY_WAIT_TIME] - Time to wait after copying output files (default=30)"
	echo "--save-summaryplot - Save summary plot with image+regions"
	echo "--save-catalog-to-json - Save catalogs to json format"
	echo "--save-bkgmap - Save bkg map"
	echo "--save-rmsmap - Save noise map"
	echo "--save-regions - Save DS9 regions (default=no)"
	echo ""

	echo "=========================="
  exit 1
fi


##########################
##    PARSE ARGS
##########################
JOB_DIR=""
JOB_OUTDIR=""
WAIT_COPY=false
COPY_WAIT_TIME=30

# - CUTEX OPTIONS
CUTEX_DIR="/opt/Software/CuTEx"
NCORES="1"
INPUT_IMAGE=""

SEED_THR="5"
NPIX_MIN="4"
NPIX_PSF="2.7"
PSF_LIM_MIN="0.5"
PSF_LIM_MAX="2"
SAVE_SUMMARY_PLOT=false
SAVE_BKG_MAP=false
SAVE_RMS_MAP=false
SAVE_DS9REGIONS=false
SAVE_CATALOG_TO_JSON=false
REDIRECT_LOGS=true
RUN_SCRIPT=false

echo "ARGS: $@"

for item in "$@"
do
	case $item in
		--cutexdir=*)
    	CUTEX_DIR=`echo "$item" | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--inputfile=*)
    	INPUT_IMAGE=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--seedthr=*)
    	SEED_THR=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--npixmin=*)
    	NPIX_MIN=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--npixpsf=*)
    	NPIX_PSF=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--psflimmin=*)
    	PSF_LIM_MIN=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--psflimmax=*)
    	PSF_LIM_MAX=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--save-summaryplot*)
    	SAVE_SUMMARY_PLOT=true
    ;;
		--save-bkgmap*)
    	SAVE_BKG_MAP=true
    ;;
		--save-rmsmap*)
    	SAVE_RMS_MAP=true
    ;;
		--save-catalog-to-json*)
    	SAVE_CATALOG_TO_JSON=true
    ;;
		--save-regions*)
    	SAVE_DS9REGIONS=true
    ;;
		--jobdir=*)
    	JOB_DIR=`echo "$item" | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--outdir=*)
    	JOB_OUTDIR=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--waitcopy*)
    	WAIT_COPY=true
    ;;
		--copywaittime=*)
    	COPY_WAIT_TIME=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--ncores=*)
      NCORES=`echo $item | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--no-logredir*)
			REDIRECT_LOGS=false
		;;
		--run*)
    	RUN_SCRIPT=true
    ;;
	*)
    # Unknown option
    echo "ERROR: Unknown option ($item)...exit!"
    exit 1
    ;;
	esac
done

# - Check arguments parsed
if [ "$INPUT_IMAGE" = "" ]; then
 	echo "ERROR: Missing input image arg!"
	exit 1
fi

if [ "$JOB_DIR" = "" ]; then
  echo "WARN: Empty JOB_DIR given, setting it to pwd ($PWD) ..."
	JOB_DIR="$PWD"
fi

if [ "$JOB_OUTDIR" = "" ]; then
  echo "WARN: Empty JOB_OUTDIR given, setting it to pwd ($PWD) ..."
	JOB_OUTDIR="$PWD"
fi


# - Extract base filename
filename=$INPUT_IMAGE
filename_base=$(basename "$INPUT_IMAGE")
file_extension="${filename_base##*.}"
filename_base_noext="${filename_base%.*}"

# - Set RMS & background map filenames
#rms_file="$filename_base_noext"'_rms.fits'
#bkg_file="$filename_base_noext"'_bkg.fits'
	
# - Set catalog filename
catalog_file="catalog-$filename_base_noext"'.dat'
catalog_tab_file="catalog-$filename_base_noext"'.tab'

# - Set DS9 region filename
ds9_file="ds9-$filename_base_noext"'.reg'
ds9_isle_file="ds9-$filename_base_noext"'_isle.reg'
ds9_comp_file="ds9-$filename_base_noext"'_comp.reg'

# - Set logfile
logfile="output_$filename_base_noext"'.log'

# - Define summary output plot filename
summary_plot_file="plot_$filename_base_noext"'.png'

# - Set config filename
configfile="config_$filename_base_noext"'.cfg'

# - Set shfile
shfile="run_$filename_base_noext"'.sh'
idlfile="run_$filename_base_noext"'.pro'


#######################################
##   DEFINE GENERATE EXE SCRIPT FCN
#######################################
generate_exec_script(){

	local shfile=$1
	
	
	echo "INFO: Creating sh file $shfile ..."
	( 
			echo "#!/bin/bash -e"
			
      echo " "
      echo " "

      echo 'echo "*************************************************"'
      echo 'echo "****         PREPARE JOB                     ****"'
      echo 'echo "*************************************************"'

      echo " "

			# - Entering job directory
      echo "echo \"INFO: Entering job dir $JOB_DIR ...\""
      echo "cd $JOB_DIR"

			# - Copy CuTex dir from /opt dir to job dir (to avoid root permission errors)
			echo "echo \"INFO: Copy CuTex soft dir $CUTEX_DIR to $JOB_DIR ...\""
			echo "cp -rp $CUTEX_DIR ."

			echo "JOB_DIR=$JOB_DIR"
			echo "CUTEX_DIR_NOBASE=${CUTEX_DIR##*/}"
			echo 'CUTEX_DIR=$JOB_DIR/$CUTEX_DIR_NOBASE'
			echo "CONFIG_FILE=$configfile"
			echo "IDL_FILE=$idlfile"

			echo 'echo "INFO: CUTEX_DIR_NOBASE: $CUTEX_DIR_NOBASE"'
			echo 'echo "INFO: CUTEX_DIR: $CUTEX_DIR"'
       
			echo " "
			
			# - Copy input file to job directory	
			echo "REMOVE_IMAGE=false"
			if [ ! -e $JOB_DIR/$filename_base ] ; then
				echo "echo \"INFO: Copying input file $filename to job dir $JOB_DIR ...\""
				echo "cp $filename $JOB_DIR"
				echo "REMOVE_IMAGE=true"
      	echo " "
			fi

			echo " "

			# - Create empty log file
			echo "touch $logfile"

			echo " "

			# - Modify wrong line in original template
			echo "echo \"INFO: Modify wrong line dirRun=dirData.* in original config template ...\""
			#sed -i "s/^dirRun=dirData.*/dirRun=\'RUNDIR\/\'/\" $CUTEX_DIR/launch_script_template_GDL_CuTEx.pro
			echo "sed -i \"s/^dirRun=dirData.*/dirRun=\'RUNDIR\/'/\" "'$CUTEX_DIR/launch_script_template_GDL_CuTEx.pro'

			# - Create GDL launch script from template, after replacing some field
			echo "echo \"INFO: Creating GDL run script from template ...\""
			echo 'cat $CUTEX_DIR/Code_CuTEx/CuTEx_100/phot_package_compile.lis | sed "s:DUMMYDIR:$CUTEX_DIR:"  > $CUTEX_DIR/Code_CuTEx/CuTEx_100/phot_package.lis'
			echo 'cat $CUTEX_DIR/launch_script_template_GDL_CuTEx.pro | sed "s:DUMMYDIR:$CUTEX_DIR:" | sed "s:RUNDIR:$JOB_DIR:" | sed "s:parameters_CuTEx.txt:$CONFIG_FILE:" > $JOB_DIR/$IDL_FILE'

			echo 'echo "*************************************************"'
      echo 'echo "****         RUN SOURCE FINDER               ****"'
      echo 'echo "*************************************************"'
      echo " "
			
			# - Define run command & args
			CMD="gdl $JOB_DIR/$idlfile"

			echo " "

			# - Run finder
			echo 'echo "INFO: Extracting sources  (CMD=$CMD) ..."'
			if [ $REDIRECT_LOGS = true ]; then			
      	echo "$CMD >> $logfile 2>&1"
			else
				echo "$CMD"
      fi

			echo 'JOB_STATUS=$?'
			echo 'echo "Source finding terminated with status=$JOB_STATUS"'

			echo " "

			if [ $SAVE_SUMMARY_PLOT = true ]; then
      	echo 'echo "*************************************************"'
      	echo 'echo "****         MAKE SUMMARY PLOT               ****"'
      	echo 'echo "*************************************************"'
      
				echo "if [ -e $JOB_DIR/$ds9_comp_file ] ; then"
				echo "  echo \"INFO: Making summary plot with input image + extracted source islands ...\""
				echo "  draw_img.py --img=$filename_base --region=$ds9_comp_file --wcs --zmin=0 --zmax=0 --cmap=gray_r --contrast=0.3 --save --outfile=$summary_plot_file"
				echo "fi"	
			fi
			
			echo " "

			echo 'echo "*************************************************"'
      echo 'echo "****         CLEAR DATA                      ****"'
      echo 'echo "*************************************************"'
     
			echo 'echo "INFO: Clearing data ..."'

			echo 'if [ $REMOVE_IMAGE = false ]; then'
			echo "  rm $JOB_DIR/$filename_base"
			echo "fi"

			echo " "

			if [ $SAVE_DS9REGIONS = false ]; then
				echo "if [ -e $JOB_DIR/$ds9_isle_file ] ; then"	
				echo "  echo \"INFO: Removing island DS9 region file $ds9_isle_file ...\""
				echo "  rm $JOB_DIR/$ds9_isle_file"
				echo "fi"

				echo " "

				echo "if [ -e $JOB_DIR/$ds9_comp_file ] ; then"	
				echo "  echo \"INFO: Removing island DS9 region file $ds9_comp_file ...\""
				echo "  rm $JOB_DIR/$ds9_comp_file"
				echo "fi"
			fi

			echo " "

      echo 'echo "*************************************************"'
      echo 'echo "****         COPY DATA TO OUTDIR             ****"'
      echo 'echo "*************************************************"'
      echo 'echo ""'
			
			if [ "$JOB_DIR" != "$JOB_OUTDIR" ]; then
				echo "echo \"INFO: Copying job outputs in $JOB_OUTDIR ...\""
				echo "ls -ltr $JOB_DIR"
				echo " "

				echo "# - Copy output plot(s)"
				echo 'png_count=`ls -1 *.png 2>/dev/null | wc -l`'
  			echo 'if [ $png_count != 0 ] ; then'
				echo "  echo \"INFO: Copying output plot file(s) to $JOB_OUTDIR ...\""
				echo "  cp *.png $JOB_OUTDIR"
				echo "fi"

				echo " "

				echo "# - Copy output jsons"
				echo 'json_count=`ls -1 *.json 2>/dev/null | wc -l`'
				echo 'if [ $json_count != 0 ] ; then'
				echo "  echo \"INFO: Copying output json file(s) to $JOB_OUTDIR ...\""
				echo "  cp *.json $JOB_OUTDIR"
				echo "fi"

				echo " "

				echo "# - Copy output tables"
				echo 'tab_count=`ls -1 *.tab 2>/dev/null | wc -l`'
				echo 'if [ $tab_count != 0 ] ; then'
				echo "  echo \"INFO: Copying output table file(s) to $JOB_OUTDIR ...\""
				echo "  cp *.tab $JOB_OUTDIR"
				echo "fi"

				echo " "

				echo "# - Copy output regions"
				echo 'reg_count=`ls -1 *.reg 2>/dev/null | wc -l`'
				echo 'if [ $reg_count != 0 ] ; then'
				echo "  echo \"INFO: Copying output region file(s) to $JOB_OUTDIR ...\""
				echo "  cp *.reg $JOB_OUTDIR"
				echo "fi"

				echo " "

				#echo "# - Copy bkg & rms maps"
				#echo "if [ -e $JOB_DIR/$bkg_file ] ; then"
				#echo "  echo \"INFO: Copying bkg map file $bkg_file to $JOB_OUTDIR ...\""
				#echo "  cp $JOB_DIR/$bkg_file $JOB_OUTDIR"
				#echo "fi"

				#echo " "
		
				#echo "if [ -e $JOB_DIR/$rms_file ] ; then"
				#echo "  echo \"INFO: Copying rms map file $rms_file to $JOB_OUTDIR ...\""
				#echo "  cp $JOB_DIR/$rms_file $JOB_OUTDIR"
				#echo "fi"  

				echo " "

				echo "# - Show output directory"
				echo "echo \"INFO: Show files in $JOB_OUTDIR ...\""
				echo "ls -ltr $JOB_OUTDIR"

				echo " "

				echo "# - Wait a bit after copying data"
				echo "#   NB: Needed if using rclone inside a container, otherwise nothing is copied"
				if [ $WAIT_COPY = true ]; then
           echo "sleep $COPY_WAIT_TIME"
        fi
	
			fi

      echo " "
      echo " "
      
      echo 'echo "*** END RUN ***"'

			echo 'exit $JOB_STATUS'

	) > $shfile

	chmod +x $shfile
}
## close function generate_exec_script()


###############################
##    CONFIG FILE GENERATOR
###############################
generate_config(){

	local configfile=$1
	local inputfile=$2

	echo "INFO: Creating config file $configfile ..."
	(
		echo '# Parameter file for the Detection and Extraction of CuTEx'
		echo "IMAGE = '$inputfile'"
		echo '# DETECTION PARAMETERS'
		echo "THRESHOLD = $SEED_THR"
		echo '#'
		echo "SMOOTH = 0"
		echo "NPIXMASK = $NPIX_MIN"
		echo "PSFPIX = $NPIX_PSF"
		echo "DERIVATE = 0"
		echo "ALL_NEIGHBOURS = 0"
		echo "THRESH = 0"
		echo "RANGE = 0"
		echo "SUPER_RESOLUTION = 0"
		echo "ABSCURV = 0"
		echo "LOCAL_THRESH = 1"
		echo "FACT_MASK = 0"
		echo '#'
		echo '# EXTRACTION PARAMETERS'
		echo '#'
		echo "MARGIN = 0"
		echo "MAX_DIST_FAC = 0"
		echo "PSFLIM = [$PSF_LIM_MIN,$PSF_LIM_MAX]"
		echo "ADAPTIVE_GROUP = 0"
		echo "CLOSEST_NEIGH = 0"
		echo "ADAPTIVE_WINDOW = 0"
		echo "DMAX_FACTOR = 0"
		echo "SMOOTHING = 0"
		echo "POSBACK = 0"
		echo "CORREL = 0"
		echo "WEIGHT = 0"
		echo "NOFORCEFIT = 0"
		echo "BACKGFIT = 0"
		echo "CENTERING = 0"
		echo "PSFPIX = $NPIX_PSF"
		echo "PEAK_SHIFT = 0"
  
		#echo '############################################'
		#echo '###    CUTEX CONFIG OPTIONS'
		#echo '############################################'
		#echo '## INPUTS'
		#echo "IMAGE = $inputfile 					        #  Filename of the INPUT image in FITS format"
		#echo '##'
		#echo '## DETECTION PARAMETERS'
		#echo "THRESHOLD = $SEED_THR								# Threshold Level adopted to identify sources"
		#echo "SMOOTH = 0													# Boolean Variable (0 -1) to apply a smoothing filter to the input image"
		#echo "NPIXMASK = $NPIX_MIN								# Minimum number of pixels for a cluster to be significant (default=4)"
		#echo "PSFPIX = $NPIX_PSF									# Number of pixels that sample the instrumental PSF on the input image"
		#echo "DERIVATE = 0												# Boolean switch (0 -1) for Derivate computing method. 0) (Default) Refined 5-points derivate, 1) General 3-points Derivate"
		#echo "ALL_NEIGHBOURS = 0									# Considers as nearest neighbouring pixels also the diagonal ones. Increases the running time if switched on"
		#echo "THRESH = 0													#	(Default not set) Define the criteria to detect multiple sources in a large pixel clusters. Internal Threshold on curvature values over the pixels of a single cluster"
		#echo "RANGE = 0														# Maximum distance in pixels from the curvature peak adopted to determine the first minima. Used to estimate the size of the candidate sources. (Default internally set: 8)"
		#echo "SUPER_RESOLUTION = 0								# (OBSOLETE) For clusters of sources. Checks curvature statistics to define how many sources there are on derivative maps in single directions instead of using the mean derivative"
		#echo "ABSCURV = 0													#	Boolean variable (0 - 1) for value of thresholding in curvature. 0) (Default) the threshold is in unit of standard deviation, 1) (not recommended) threshold is set in Absolute Curvature Values"
		#echo "LOCAL_THRESH = 1										# Boolean variable (0 - 1) one methods to compute the comparison threshold level. If active (suggested) the standard deviation is computed locally on derivative maps as the median deviation form the median (MAD) in boxes of 61x61 pixels, and is applied to boxes of 31x31 over the entire map" 
		#echo "FACT_MASK = 0												# Factor to assign the masked region ascribed to sources that is adopted for the fitting. (Default = 2)"
	  #echo '##'
		#echo '## EXTRACTION PARAMETERS'
		#echo "MARGIN = 0													# Cutoff in pixels avoiding to extract sources detected too close to the image margin"
		#echo "MAX_DIST_FAC = 0										# Length adopted to group sources together for simultaneous fitting (if adaptive_group = 0 it is in units of PSF, on the contrary it is in units of estimated source FWHMs)"
		#echo "PSFLIM = [$PSF_LIM_MIN,$PSF_LIM_MAX] # Defines the interval adopted for fitting the source size. Two-values array with lower and upper limiting variation with respect to the initial source size (i.e. [0.7,1.3] means +/- 30%  Guessed Size ). default: [0.5,2.0]"
		#echo "ADAPTIVE_GROUP = 0									# (Default 0) Change units adopted to create group of sources. 0) (Default) Length is expressed in terms of PSF, 1) it is expressed in terms of Guessed Source Size"
		#echo "CLOSEST_NEIGH = 0										# (Default 0) Boolean Variable to determine which measurements keep when multiple sources are fitted simultaneously. 0) (Default) keep the parameters for all the sources, 1) Cicle over each source and repeat the fitting procedure, and keep the output values only for current source (Very slow process)"
		#echo "ADAPTIVE_WINDOW = 0									# (Default 0) Boolean Variable to change units in defining the size of the subframe adopted to fit the source. 0) The size of the window is determined in terms of PSF, 1) it is derived from the initial guessed size of the source." 
		#echo "DMAX_FACTOR = 0											# Size of the fitting window extracted to evaluate source fluxes (if adaptive_window is on it is in units of PSF, on the contrary it is in units of estimated source FWHMs)"
		#echo "SMOOTHING = 0												# Width (in pixels) of boxcar smoothing window to be applied before the extractiones"
		#echo "POSBACK = 0													# Forces the fitted background to be positive (Default on)"
		#echo "CORREL = 0													# (Default on): Assume that that peak flux and size of fitted sources are correlated in error calculation"
		#echo "WEIGHT = 0													# (Default off): Assign larger weights to source pixels with respect to the pixels assigned to the background"
		#echo "NOFORCEFIT = 0											# (Default off): Leave free the interval of parameters for sources for which it was not possible to determine a proper guessed size"
		#echo "BACKGFIT = 0												# (Default 0): Boolean variable setting the polynomial shape of background adopted for fitting. 0) Simple plane with inclination (A*x + B*y + C), 1) Second order polynomial function with mixed terms (6 - variable function)"
		#echo "CENTERING = 0												# (Default off): Boolean variable. If set on, it centers the subframe on the baricentre of the group of sources that is being fitted, on the contrary it centers the subframe on individual sources when multiple objects are fitted"
		#echo "PSFPIX = $NPIX_PSF							    # Size of the PSF in pixels sampled on the data."
		#echo "PEAK_SHIFT = 0											# Interval in pixels to allow the maximum shift of source centre during the fit"

 ) > $configfile

}
## close function








###############################
##    RUN CUTEX
###############################
# - Check if job directory exists
if [ ! -d "$JOB_DIR" ] ; then 
  echo "INFO: Job dir $JOB_DIR not existing, creating it now ..."
	mkdir -p "$JOB_DIR" 
fi

# - Moving to job directory
echo "INFO: Moving to job directory $JOB_DIR ..."
cd $JOB_DIR

# - Generate configuration file
echo "INFO: Creating config file $configfile ..."
generate_config $configfile $filename_base

# - Generate run script
echo "INFO: Creating run script file $shfile ..."
generate_exec_script "$shfile"

# - Launch run script
if [ "$RUN_SCRIPT" = true ] ; then
	echo "INFO: Running script $shfile to local shell system ..."
	$JOB_DIR/$shfile
fi


echo "*** END SUBMISSION ***"



#pushd $dirRun
#mainFiles=$(cat list_mainOutputs.txt)
#jj=''
#for ii in ${mainFiles[*]}; do jj=$jj' '$ii;done
#echo 'tar -cvf resultsMain.tar '$jj
#tar -cvf resultsMain.tar $jj
#echo 'Storing Main Outputs : '$jj

#auxFiles=$(cat list_auxiliaryOutputs.txt)
#jj=''
#for ii in ${auxFiles[*]}; do jj=$jj' '$ii;done
#echo 'tar -cvf resultsAux.tar '$jj
#tar -cvf resultsAux.tar $jj
#echo 'Storing Auxiliary Outputs :'$jj

#echo 'Data are store and available at '$dirRun
#echo ' 			- Main Outputs: resultsMain.tar'
#echo ' 			- Auxiliary Outputs resultsAux.tar'

#popd

