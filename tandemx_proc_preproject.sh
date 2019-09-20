#! /bin/bash

#Download and process TanDEM-X 90-m products

############# Configuration ################
#Follow Configuration steps below

#Step 1 - Define the working directory - make sure it exists
#topdir=/data/puma1/scratch/mtnglaME/tdx/pcr/
topdir=/data/puma1/scratch/mtngla/Tdx/hma/

#Step 2 - Get list of input files. Save list by cmd-click and downloading list - save it in the working folder defined above.
#https://download.geoservice.dlr.de/TDM90/
#Name the list something sensible like TDM90-url-list_alaska.txt

#Step 3 - input the name of your saved list - this must be in your working directory:
#url_list=TDM90-url-list_pcr_bbox.txt
url_list=TDM90-url-list_hma_bbox.txt

#Step 4 - Set username and password 
uname='ADD USER NAME HERE'
#Quotes required for special characters in pw
pw='ADD PASSWORD HERE'

# Step 5 - Set the area name (can be anything you'd like):
#export site='pcr'
export site='hma'

# Step 6 - set the projection, bounding box and resolution:
#export proj='+proj=stere +lat_0=90 +lat_ts=70 +lon_0=-45 +k=1 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs'
export proj='+proj=aea +lat_1=25 +lat_2=47 +lat_0=36 +lon_0=85 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs'

#PCR
#export bbox='-3909240.000 -678960.000 -2196270.000 2352600.000'
#export res='90 90'

#HMA
export bbox='-1787220 -1122930 1491930 810720'
export res='90 90'


# Step 7 - run this file from the command line './tandemx_proc.sh'. The output tif will be placed in the mos folder in the working directory.


############# Code Begins ################

#Turn off auto ls after cd
unset -f cd

#Location for additional processing scripts, assumed to be in same directory as this script
#srcdir=~/src/tandemx
srcdir=$(dirname "$(readlink -f "$0")")

#Change to working directory
cd $topdir

#Download
parallel --progress -j 8 "wget --auth-no-challenge --user=$uname --password=$pw -nc {}" < $url_list
parallel --progress 'unzip {}' ::: *.zip

#Process

#Gdal options
export gdal_opt="-co COMPRESS=LZW -co TILED=YES -co BIGTIFF=IF_SAFER"

#mos folder
export mosdir='mos'
if [ ! -d $mosdir ] ; then
    mkdir -pv $mosdir
fi

#This is original ndv
ndv=-32767
parallel --progress "gdal_edit.py -a_nodata $ndv {}" ::: TDM1_DEM*_C/DEM/*DEM.tif TDM1_DEM*_C/AUXFILES/*HEM.tif
parallel --progress "gdal_edit.py -a_nodata 0 {}" ::: TDM1_DEM*_C/AUXFILES/*{AM2,AMP,WAM,COV,COM,LSM}.tif

#Cleanup existing files:
rm TDM1_DEM*_C/DEM/*projected.tif
rm TDM1_DEM*_C/DEM/*masked.tif
rm TDM1_DEM*_C/AUXFILES/*projected.tif

#Project Individual tiles
parallel --progress --link 'gdalwarp -overwrite -r cubic -tr $res -t_srs "${proj}" $gdal_opt -tap -et 0 {.}.tif {.}_projected.tif' ::: TDM1_DEM*_C/DEM/*DEM.tif
parallel --progress --link 'gdalwarp -overwrite -r near -tr $res -t_srs "${proj}" $gdal_opt -tap -et 0 {.}.tif {.}_projected.tif' ::: TDM1_DEM*_C/AUXFILES/*{HEM,AM2,AMP,WAM,COV,COM,LSM}.tif

#Mask Projected DEM file using err products
parallel --progress "$srcdir/tandemx_mask_proj.py {}" ::: TDM1_DEM*_C

#Mask DEM file using err products
parallel --progress "$srcdir/tandemx_mask.py {}" ::: TDM1_DEM*_C

cd $mosdir

function proc_lyr() {
    lyr=$1
    lyr_list=$(ls ../TDM1*/*/*$lyr.tif)
    vrt=TDM1_DEM_${site}_${lyr}.vrt
    gdalbuildvrt $vrt $lyr_list
    cd ..
}

export -f proc_lyr
ext_list="DEM DEM_projected DEM_masked DEM_projected_masked"
parallel --progress "proc_lyr {}" ::: $ext_list

#Merge

lyr=DEM_projected
vrt=TDM1_DEM_${site}_${lyr}.vrt
gdalwarp -overwrite -r cubic -tr $res -t_srs "$proj" -te $bbox $gdal_opt -tap -et 0 $vrt ${vrt%.*}_output.tif

lyr=DEM_projected_masked
vrt=TDM1_DEM_${site}_${lyr}.vrt
gdalwarp -overwrite -r cubic -tr $res -t_srs "$proj" -te $bbox $gdal_opt -tap -et 0 $vrt ${vrt%.*}_output.tif

