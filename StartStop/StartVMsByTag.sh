#!/bin/bash

az vm start --no-wait --ids $(az resource list --tag "$1" --query "[?type=='Microsoft.Compute/virtualMachines'].id" -o tsv)