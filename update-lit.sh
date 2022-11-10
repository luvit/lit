#!/bin/bash

cecho() {
	# foreground \033[48;2;RRR;GGG;BBBm
	# background \033[38;2;RRR;GGG;BBBm
	# clear      \033[0m

	echo -e "\033[38;2;50;210;255m$1\033[0m";
}

while test $# -gt 0; do
	case "$1" in
		-l|-last|--lastest )
			cecho 'Checking the lit version...'
			LIT_VERSION=$(curl https://api.github.com/repos/luvit/lit/tags | grep -o -P '(?<=\"name\": \").*(?=\",)' | head -1);
			cecho "Lastest lit release: $LIT_VERSION";

			cecho 'Checking the luvi version...'
			LUVI_VERSION=$(curl https://api.github.com/repos/luvit/luvi/releases/latest | grep -o -P '(?<=\"tag_name\": \"v).*(?=\",)');
			cecho "Lastest luvi release: $LUVI_VERSION";

			break;
		;;
		-lit-ver|--lit-version )
			LIT_VERSION=$2;
			shift 2;
		;;
		-luvi-ver|--luvi-version )
			LUVI_VERSION=$2;
			shift 2;
		;;
		-h|--help)
		cecho 'luvit-update - a update tool for lit/luvi/luvit';
		echo ' ';
		cecho 'luvit-update [options] [arguments]';
		echo ' ';
		cecho 'options:';
		cecho '-h, --help                             Show help.';
		cecho '-l, -last, --lastest                   Download lastest lit/luvi/luvit releases from github (by default updater works with versions get-lit.sh that updates manually).';
		cecho '-lit-ver XXX, --lit-version YYY        Specify an lit version.';
		cecho '-luvi-ver XXX, --luvi-version YYY      Specify an luvit version.';
		exit 0;
		;;
		*)
			break;
		;;
	esac
done;

if [ ! $LIT_VERSION ] || [ ! $LUVI_VERSION ]; then
	cecho 'Request versions from get-lit.sh';
	GET_LIT=$(curl 'https://raw.githubusercontent.com/luvit/lit/master/get-lit.sh');

	if [ !$LIT_VERSION ]; then
		LIT_VERSION=$(cecho "$GET_LIT" | grep -o -P '(?<=\${LIT_VERSION:-).*(?=})');
		cecho "Lit release: $LIT_VERSION (may a bit outdated)";
	fi
	if [ !$LUVI_VERSION ]; then
		LUVI_VERSION=$(cecho "$GET_LIT" | grep -o -P '(?<=\${LUVI_VERSION:-).*(?=})');
		cecho "Luvi release: $LUVI_VERSION (may a bit outdated)";
	fi
fi

update() {
	LUVI_ARCH=`uname -s`_`uname -m`;
	LUVI_URL="https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-regular-$LUVI_ARCH";
	LIT_URL="https://lit.luvit.io/packages/luvit/lit/v$LIT_VERSION.zip";

	rm lit 2> /dev/null & rm luvi 2> /dev/null & rm luvit 2> /dev/null;

	# Download Files
	cecho "Downloading $LUVI_URL to luvi"
	curl -L -f -o luvi $LUVI_URL
	chmod +x luvi
	cecho "Downloading $LIT_URL to lit.zip"
	curl -L -f -o lit.zip $LIT_URL
	# Create lit using lit
	./luvi lit.zip -- make lit.zip lit luvi
	# Cleanup
	rm -f lit.zip
	# Create luvit using lit
	./lit make lit://luvit/luvit luvit luvi

	exit 0;
}

if ! command -v lit > /dev/null
then
	cecho '  Lit is not installed';
	update;
fi

if ! command -v luvi > /dev/null
then
	cecho '  Luvi is not installed';
	update;
fi

if ! command -v luvit > /dev/null
then
	cecho '  Luvit is not installed';
	update;
fi

LIT_VERSION_CUR=$(lit -v | grep -m1 -Po 'lit version:\s\K.*');
cecho "Installed version of lit: $LIT_VERSION_CUR";

if [ "$LIT_VERSION" != "$LIT_VERSION_CUR" ]; then
	cecho '  Lit needs update';
	cecho "  $LIT_VERSION != $LIT_VERSION_CUR";
	update;
fi

LUVI_VERSION_CUR=$(luvi -v | grep -m1 -Po 'luvi v\K.*');
cecho "Installed version of luvi: $LUVI_VERSION_CUR";

if [ "$LUVI_VERSION" != "$LUVI_VERSION_CUR" ]; then
	cecho '  Luvi needs update';
	cecho "  $LUVI_VERSION != $LUVI_VERSION_CUR";
	update;
fi

cecho 'No update required';
