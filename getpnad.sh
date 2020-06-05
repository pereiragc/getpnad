#!/bin/bash

# Copyright (C) 2020  Gustavo Pereira

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


set -euo pipefail

#
# Adjustable parameters (only change this if you know what you're doing)
base_url="ftp://ftp.ibge.gov.br/Trabalho_e_Rendimento/Pesquisa_Nacional_por_Amostra_de_Domicilios_continua/Trimestral/Microdados"
rest_time=2




err() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $@" >&2; exit 1;
}

usage() { echo "Usage: $0 [-b YYYY] [-e YYYY] [-d (yes|no|only)]" 1>&2; exit 1; }

dic_opt="yes"
year_begin=2012
year_end=2012

while getopts "d:b:e:" opt; do
    case $opt in
        d)
            dic_opt=$OPTARG
            [[ "$dic_opt" == "yes" || "$dic_opt" == "no" ]] || \
                [[ "$dic_opt" == "only" ]] || \
                usage
            ;;
        b)
            year_begin=$OPTARG
            [[ "$year_begin" =~ 20[012][0-9] ]] || usage
            ;;
        e)
            year_end=$OPTARG
            [[ "$year_end" =~ 20[012][0-9] ]] || usage

            # Verify that it makes sense given $year_begin
            [[ "$dic_opt" == "only"  ]] || [[ -z "$year_begin" ]] || \
                [[ $year_begin -le $year_end ]] || \
                err "Please use sensible begin/end dates"
            ;;
        :)
            echo "Option $opt requires an argument." >&2
            exit 1
            ;;
    esac
done

# DEFAULT ARGS  -----------------------------------------------------------------

if [[ "$dic_opt" == "only" ]]; then
    [[ -n "$year_begin" ]] && echo "Option -b set with -d only; overriding"
    [[ -n "$year_end" ]] && echo "Option -e set with -d only; overriding"
    year_begin="[doc_only]"
    year_end="[doc_only]"
fi


# For download range:
if [[ -z "$year_begin" ]] && [[ -n "$year_end" ]]; then
    year_begin=$year_end
fi
if [[ -z "$year_end" ]] && [[ -n "$year_begin" ]]; then
    year_end=$year_begin
fi


echo " "
echo "Proceeding to download. Options:"
echo ".. Start year: $year_begin"
echo ".. End year: $year_end"
echo ".. Dictionary: $dic_opt"


# CHECK DIRECTORY ---------------------------------------------------------------

currpath=$(pwd)
currdir=${currpath##*/}
prevdirpath=$(dirname $currpath)
prevdir=${prevdirpath##*/}

#
# If non existent, create data & tmp directory
mkdir -p .tmp
cd .tmp




# START MAIN PART


if [[ "$dic_opt" != "no" ]]; then

    echo " "
    echo "Downloading dictionary..."


    # Try to find dictionary: how many matches?
    lfiles=$(curl -s -l "$base_url/Documentacao/")
    nm=$(echo $lfiles | grep -c "Dicionario_e_input")
    if [[ $nm -eq 0 ]]; then
        # zero matches
        cd ..
        err "Dictionary file not found"
    fi
    if [[ $nm -gt 2 ]]; then
        # more than one match
        echo "WARNING: Multiple dictionary files; downloading first one"
    fi

    dict_file=$(grep -m 1 "Dicionario_e_input" <<<$lfiles)
    curl -# "$base_url/Documentacao/$dict_file" -o "doc.zip"

    doc_contents=$(unzip -ql doc.zip)

    # Look for the text file
    nm=$(grep -c ".txt$" <<<$doc_contents)

    if [[ $nm -ne 1 ]]; then
       err "Either no text file or more than one in $dict_file"
    fi


    # If reach here, everything seems fine, so download and move dictionary.
    unzip -q doc.zip "*.txt"

    file_check=$(find . -iregex ".*txt$")

    if [[  "$file_check"  == "" ]]; then
       err "Error unziping text file"
    fi

    mv $file_check ../
    sleep $rest_time
fi

if [[ "$dic_opt" == "only" ]]; then
   exit 0
fi

echo " "
echo "Starting data download."

this_year=$year_begin
while [[ "$this_year" -ge "$year_begin" && "$this_year" -le "$year_end" ]]; do

    # List files in current year
    lfiles=$(curl -s -l "$base_url/$this_year/" | grep "\.zip$")

    while IFS= read -r f; do

        q=$(echo $f | sed -e "s/PNADC_\(0.\)[0-9]\{4\}.*\.zip$/\1/")
        newname="pnad_${this_year}_q${q}.zip"

        curl -# "$base_url/$this_year/$f" -o \
             "$newname"

        # Move file to adequate place
        mv $newname ../
    done  <<< "$lfiles"

    echo " "
    echo "Year $this_year downloaded."

    sleep $rest_time
    this_year=$((this_year+1))
done
