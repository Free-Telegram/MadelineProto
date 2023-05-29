#!/bin/bash -e

# Configure
sed 's/;phar.readonly = On/phar.readonly = 0/g' -i /usr/local/etc/php/php.ini
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer

curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
apt-get update
apt-get -y install procps git unzip gh

echo "$TAG" | grep -q '\.9999' && exit 0 || true
echo "$TAG" | grep -q '\.9998' && exit 0 || true

PHP_MAJOR_VERSION=$(php -r 'echo PHP_MAJOR_VERSION;')
PHP_MINOR_VERSION=$(php -r 'echo PHP_MINOR_VERSION;')
php=$PHP_MAJOR_VERSION$PHP_MINOR_VERSION

COMMIT="$(git log -1 --pretty=%H)"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT_MESSAGE="$(git log -1 --pretty=%B HEAD)"

git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
git config --global user.name "Github Actions"

if [ "$TAG" == "" ]; then
    export TAG=7777
    git tag "$TAG"
    git checkout "$TAG"
fi

export TEST_SECRET_CHAT=test
export TEST_USERNAME=danogentili
export TEST_DESTINATION_GROUPS='["@danogentili"]'
export MTPROTO_SETTINGS='{"logger":{"logger_level":5}}'

echo "PHP: $php"
echo "Branch: $BRANCH"
echo "Commit: $COMMIT"
echo "Latest tag: $TAG"

# Clean up
madelinePath=$PWD

k()
{
    while :; do pkill -f "MadelineProto worker $(pwd)/tests/../testing.madeline" || break && sleep 1; done
}

k
rm -rf madeline.phar testing.madeline*

composer update
#vendor/bin/phpunit tests/danog/MadelineProto/EntitiesTest.php

COMPOSER_TAG="$TAG"

rm -rf vendor*
git reset --hard
git checkout "$COMPOSER_TAG"

cd ..
rm -rf phar
mkdir phar

cd phar

# Install

mkdir -p ~/.composer
echo '{"github-oauth": {"github.com": "'$GITHUB_TOKEN'"}}' > ~/.composer/auth.json

echo '{
    "name": "danog/madelineprotophar",
    "require": {
        "danog/madelineproto": "'$COMPOSER_TAG'"
    },
    "minimum-stability": "beta",
    "authors": [
        {
            "name": "Daniil Gentili",
            "email": "daniil@daniil.it"
        }
    ],
    "repositories": [
        {
            "type": "path",
            "url": "'$madelinePath'",
            "options": {"symlink": false}
        }
    ]
}' > composer.json
php $(which composer) update --no-cache
php $(which composer) dumpautoload --optimize
rm -rf vendor/danog/madelineproto/docs vendor/danog/madelineproto/vendor-bin
mkdir -p vendor/danog/madelineproto/src/danog/MadelineProto/Ipc/Runner
cp vendor/danog/madelineproto/src/Ipc/Runner/entry.php vendor/danog/madelineproto/src/danog/MadelineProto/Ipc/Runner
cd ..

branch="-$BRANCH"
cd $madelinePath

db()
{
    php tests/db.php $1 $2
}
cycledb()
{
    for f in serialize igbinary; do
        db memory $f
        db mysql $f
        db postgres $f
        db redis $f
        db memory $f
    done
}

runTestSimple()
{
    {
        echo "n
n
n
"; } | tests/testing.php
}
runTest()
{
    {
        echo "b
$BOT_TOKEN
n
n
n
"; } | $p tests/testing.php
}

k
rm -f madeline.phar testing.madeline*

tail -F MadelineProto.log &

echo "Testing with previous version..."
export ACTIONS_FORCE_PREVIOUS=1
cp tools/phar.php madeline.php
runTest
db mysql serialize
k

echo "Testing with new version (upgrade)..."
rm -f madeline-*phar madeline.version

php tools/makephar.php $madelinePath/../phar "madeline$php$branch.phar" "$COMMIT-81"
cp "madeline$php$branch.phar" "madeline-TESTING.phar"
echo -n "TESTING" > "madeline.version"
echo 0.0.0.0 phar.madelineproto.xyz > /etc/hosts
cp tools/phar.php madeline.php
export ACTIONS_PHAR=1
runTestSimple
cycledb
k

echo "Testing with new version (restart)"
rm -rf testing.madeline || echo
runTest

echo "Testing with new version (reload)"
runTestSimple
k

echo "Testing with new version (kill+reload)"
runTestSimple
k

echo "Checking syntax of madeline.php"
php -l ./tools/phar.php

input=$PWD

cd "$madelinePath"

if [ "$TAG" == "7777" ]; then exit 0; fi

cp "$input/madeline$php$branch.phar" "madeline81.phar"
git remote add hub https://github.com/danog/MadelineProto
gh release upload "$TAG" "madeline81.phar"
rm "madeline81.phar"

gh release edit --prerelease=false "$TAG"
gh release edit --latest=true "$TAG"

if [ "$DEPLOY_KEY" != "" ]; then
    mkdir -p $HOME/.ssh
    ssh-keyscan -t rsa github.com >> $HOME/.ssh/known_hosts
    echo "$DEPLOY_KEY" > $HOME/.ssh/id_rsa
    chmod 0600 $HOME/.ssh/id_rsa
fi

git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
git config --global user.name "Github Actions"

input=$PWD

cd /tmp
git clone git@github.com:danog/MadelineProtoPhar.git
cd MadelineProtoPhar

cp "$input/tools/phar.php" .
for php in 81; do
    echo -n "$COMMIT-$php" > release$php
done

git add -A
git commit -am "Release $BRANCH - $COMMIT_MESSAGE"
while :; do
    git push origin master && break || {
        git fetch
        git rebase origin/master
    }
done
