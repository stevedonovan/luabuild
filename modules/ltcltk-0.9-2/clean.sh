#!/bin/sh

find . -name "*~" -exec rm {} \;
rm -f *.o *.so *.func *.ps core

for dir in . doc samples
do
	rm -f $dir/.DS_Store
	rm -f $dir/._*
done

