#  expectValue = "SUCCESS"
#  scriptTimeout = 2
#  replayEnabled = true
#  replayTimeout = 20

#  expectValue = "SUCCESS"
#  scriptTimeout = 2
#  replayEnabled = true
#  replayTimeout = 20

FLAG='FAIL'

bigip_private_key='/etc/ssl/private/dewpt_private.pem'
bastion_private_key='/etc/ssl/private/dewpt_private.pem'
if [[ "<CREATE NEW KEY PAIR>" == 'true' ]]; then
    # created by verify_login.sh
    bigip_private_key='/etc/ssl/private/new_key.pem'
    if [[ "<STACK TYPE>" == "full-stack" ]]; then
        bastion_private_key='/etc/ssl/private/new_key.pem'
    fi
fi
echo "Private key: ${bigip_private_key}"
echo "Bastion private key: ${bastion_private_key}"

PASSWORD='<SECRET VALUE>'
if [[ "<CREATE NEW SECRET>" == 'true' ]]; then
    unique_string=$(aws cloudformation describe-stacks --stack-name <STACK NAME> --region <REGION> | jq -r '.Stacks[].Parameters[] | select (.ParameterKey=="uniqueString") | .ParameterValue')
    secret_name=${unique_string}-bigIpSecret
    PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${secret_name} --region <REGION> | jq -r .SecretString)
    echo "Unique string: ${unique_string}"
    echo "Secret name: ${secret_name}"
fi
echo "PASSWORD: ${PASSWORD}"

bigip1_stackname=$(aws cloudformation describe-stacks --stack-name <STACK NAME> --region <REGION> | jq -r '.Stacks[].Outputs[] | select (.OutputKey=="bigIpInstance01") | .OutputValue')
bigip1_instance_id=$(aws cloudformation describe-stacks --stack-name  ${bigip1_stackname} --region <REGION> | jq -r '.Stacks[].Outputs[]|select (.OutputKey=="bigIpInstanceId")| .OutputValue')
bigip2_stackname=$(aws cloudformation describe-stacks --stack-name <STACK NAME> --region <REGION> | jq -r '.Stacks[].Outputs[] | select (.OutputKey=="bigIpInstance02") | .OutputValue')
bigip2_instance_id=$(aws cloudformation describe-stacks --stack-name  ${bigip2_stackname} --region <REGION> | jq -r '.Stacks[].Outputs[]|select (.OutputKey=="bigIpInstanceId")| .OutputValue')


echo "BIGIP1 Instance Id: $bigip1_instance_id"
echo "BIGIP2 Instance Id: $bigip2_instance_id"

if [[ '<PROVISION MGMT PUBLIC IP>' == 'false' ]]; then
    echo 'MGMT PUBLIC IP IS NOT ENABLED'

	if [[ "<STACK TYPE>" == "existing-stack" ]]; then
        bastion_public_ip=$(aws cloudformation describe-stacks --stack-name bastion-<STACK NAME> --region <REGION> | jq -r '.Stacks[].Outputs[] | select (.OutputKey=="bastionPublicIp") | .OutputValue')
    else
        bastion_instance_id=$(aws cloudformation describe-stacks --stack-name <STACK NAME> --region <REGION> | jq -r '.Stacks[].Outputs[] | select (.OutputKey=="bastionHostInstanceId") | .OutputValue')
        echo "BASTION Instance Id: $bastion_instance_id"

        bastion_public_ip=$(aws ec2 describe-instances --region  <REGION> --instance-ids $bastion_instance_id | jq -r .Reservations[0].Instances[0].PublicIpAddress)
    fi
    echo "BASTION PUBLIC IP: $bastion_public_ip"
    
    bigip1_private_ip=$(aws cloudformation describe-stacks --stack-name <STACK NAME> --region <REGION> | jq -r '.Stacks[].Outputs[] | select (.OutputKey=="bigIpInstanceMgmtPrivateIp01") | .OutputValue')
    echo "BIGIP1 PRIVATE IP: $bigip1_private_ip"

    bigip2_private_ip=$(aws cloudformation describe-stacks --stack-name <STACK NAME> --region <REGION> | jq -r '.Stacks[].Outputs[] | select (.OutputKey=="bigIpInstanceMgmtPrivateIp02") | .OutputValue')

    state=$(sshpass -p ${PASSWORD} ssh -o "StrictHostKeyChecking no" -o ProxyCommand="ssh -o 'StrictHostKeyChecking no' -i ${bastion_private_key} -W %h:%p ec2-user@$bastion_public_ip" admin@${bigip1_private_ip} "tmsh show sys failover")
    state2=$(sshpass -p ${PASSWORD} ssh -o "StrictHostKeyChecking no" -o ProxyCommand="ssh -o 'StrictHostKeyChecking no' -i ${bastion_private_key} -W %h:%p ec2-user@$bastion_public_ip" admin@${bigip2_private_ip} "tmsh show sys failover")
else
    echo 'MGMT PUBLIC IP IS ENABLED'

    bigip1_public_ip=$(aws ec2 describe-instances --region  <REGION> --instance-ids $bigip1_instance_id | jq -r .Reservations[0].Instances[0].PublicIpAddress)
    echo "BIGIP1 PRIVATE IP: $bigip1_public_ip"
    bigip2_public_ip=$(aws ec2 describe-instances --region  <REGION> --instance-ids $bigip2_instance_id | jq -r .Reservations[0].Instances[0].PublicIpAddress)
    echo "BIGIP2 PRIVATE IP: $bigip2_public_ip"

    state=$(sshpass -p ${PASSWORD} ssh -o "StrictHostKeyChecking no" admin@${bigip1_public_ip} "tmsh show sys failover")
    state2=$(sshpass -p ${PASSWORD} ssh -o "StrictHostKeyChecking no" admin@${bigip2_public_ip} "tmsh show sys failover")
fi

echo "State: $state"
echo "State2: $state2"

# evaluate result
if echo $state | grep 'active' && echo $state2 | grep 'standby'; then
    echo "SUCCESS"
elif echo $state2 | grep 'active' && echo $state | grep 'standby'; then
    echo "SUCCESS"
fi
