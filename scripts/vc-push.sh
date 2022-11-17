set -a
. $1
set +a

# env_vars=`cat "$1" | sed s/=.*//g`
env_vars=`cat "$1" | sed s/=.*//g`

echo $env_vars

for key in $(echo $env_vars)
do

echo "Checking " - $key

if [[ $key =~ ^\#.*$ ]]
then
    echo "Skipping the commented value" - $key
else
    echo "Uploading" - $key
    #sleep 2 #For vercel API
    vc env rm ${key} $2  -y
    echo "${!key}" | vc env add $key $2 production
    echo "${!key}" | vc env add $key $2 preview
    echo "${!key}" | vc env add $key $2 development
fi
done

exit 0;
