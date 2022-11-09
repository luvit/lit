#!/bin/sh

echo 'Checking for available updates...';

GET_LIT=$(curl 'https://raw.githubusercontent.com/luvit/lit/master/get-lit.sh')

shouldUpdate() {
	use "$GET_LIT";

	if ! command -v lit > /dev/null
	then
		echo 'Lit not installed';
		return 0;
	fi

	if ! command -v luvi > /dev/null
	then
		echo 'Luvi not installed';
		return 0;
	fi

	if ! command -v luvit > /dev/null
	then
		echo 'Luvit not installed';
		return 0;
	fi

	CUR_LIT=$(lit -v | grep -m1 -Po 'lit version:\s\K.*');
	ACTUAL_LIT=$(echo "$GET_LIT" | grep -o -P "(?<=\${LIT_VERSION:-).*(?=})");

	if [ "$CUR_LIT" != "$ACTUAL_LIT" ]; then
		echo 'Lit needs update';
		return 0;
	fi

	CUR_LUVI=$(luvi -v | grep -m1 -Po 'luvi version:\s\K.*');
	ACTUAL_LUVI=$(echo "$GET_LIT" | grep -o -P "(?<=\${LUVI_VERSION:-).*(?=})");

	if [ "$CUR_LUVI" != "$ACTUAL_LUVI" ]; then
		echo 'Luvi needs update';
		return 0;
	fi

	CUR_LUVIT=$(luvit -v | grep -m1 -Po 'luvit version:\s\K.*');
	ACTUAL_LUVIT=$(curl https://api.github.com/repos/luvit/luvit/releases/latest | grep -o -P "(?<=\"name\": \").*(?=\",)");

	if [ "$CUR_LUVIT" != "$ACTUAL_LUVIT" ]; then
		echo 'Luvit needs update';
		return 0;
	fi

	return 1;
}

if shouldUpdate; then
	echo 'Update...';
	cd '/usr/bin/' || exit;
	bash -c "$GET_LIT";
fi
