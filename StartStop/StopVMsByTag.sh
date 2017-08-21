#!/bin/bash

az vm deallocate --no-wait --ids $(az resource list --tag "$1" --query "[?type=='Microsoft.Compute/virtualMachines'].id" -o tsv)