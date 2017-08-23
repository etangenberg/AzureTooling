
for /f %%i in ('az resource list --tag "%1" --query "[?type=='Microsoft.Compute/virtualMachines'].id" -o tsv') do set ids=%%i

ECHO %ids%
az vm deallocate --no-wait --ids %ids%