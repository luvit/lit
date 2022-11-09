#!/bin/sh

echo 'Checking for available updates...';

GET_LIT=$(curl 'https://raw.githubusercontent.com/luvit/lit/master/get-lit.sh')

shouldUpdate() {
	if ! command -v lit > /dev/null
	then
		echo 'Lit is not installed';
		return 0;
	fi

	if ! command -v luvi > /dev/null
	then
		echo 'Luvi is not installed';
		return 0;
	fi

	if ! command -v luvit > /dev/null
	then
		echo 'Luvit is not installed';
		return 0;
	fi

	echo 'Checking the lit version...';

	CUR_LIT=$(lit -v | grep -m1 -Po 'lit version:\s\K.*');
	ACTUAL_LIT=$(echo "$GET_LIT" | grep -o -P '(?<=\${LIT_VERSION:-).*(?=})');

	echo "  Actual version: $ACTUAL_LIT";
	echo "  Installed version: $CUR_LIT";

	if [ "$CUR_LIT" = "$ACTUAL_LIT" ]; then
		echo '  Latest version is installed';
	else
		echo '  Lit needs update';
		echo "  $ACTUAL_LIT > $CUR_LIT";
		return 0;
	fi

	echo 'Checking the luvi version...';

	CUR_LUVI=$(luvi -v | grep -m1 -Po 'luvi\s\K.*');
	ACTUAL_LUVI=$(echo "$GET_LIT" | grep -o -P '(?<=\${LUVI_VERSION:-).*(?=})');

	echo "  Actual version: $ACTUAL_LUVI";
	echo "  Installed version: $CUR_LUVI";

	if [ "$CUR_LUVI" = "$ACTUAL_LUVI" ]; then
		echo '  Latest version is installed';
	else
		echo '  Luvi needs update';
		echo "  $ACTUAL_LUVI > $CUR_LUVI";
		return 0;
	fi

	echo 'Checking the luvit version...';

	CUR_LUVIT=$(luvit -v | grep -m1 -Po 'luvit version:\s\K.*');
	ACTUAL_LUVIT=$(curl https://api.github.com/repos/luvit/luvit/releases/latest | grep -o -P '(?<=\"name\": \").*(?=\",)');

	echo "  Actual version: $ACTUAL_LUVIT";
	echo "  Installed version: $CUR_LUVIT";

	if [ "$CUR_LUVIT" = "$ACTUAL_LUVIT" ]; then
		echo '  Latest version is installed';
	else
		echo '  Luvit needs update';
		echo "  $ACTUAL_LUVIT > $CUR_LUVIT";
		return 0;
	fi

	return 1;
}

cd '/usr/bin/' || exit;

if shouldUpdate; then
	echo 'Update...';
	rm lit & rm luvi & rm luvit;
	bash -c "$GET_LIT";
fi
