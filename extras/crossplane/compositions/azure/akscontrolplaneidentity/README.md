# AKSControlPlaneIdentity

Creates the user-assigned identity a private AKS cluster with a BYO private DNS
zone needs for its control plane, plus the role assignments that go with it:

| Role                          | Principal                | Scope                        |
|-------------------------------|--------------------------|------------------------------|
| Private DNS Zone Contributor  | control-plane identity   | `spec.privateDNSZoneID`      |
| Network Contributor           | control-plane identity   | `spec.virtualNetworkID`      |
| Managed Identity Operator     | `spec.asoPrincipalID`    | the control-plane identity   |
| anything in `spec.additionalRoleAssignments` | control-plane identity | per entry |

## Usage

```yaml
apiVersion: crossplane.giantswarm.io/v1alpha1
kind: AKSControlPlaneIdentity
metadata:
  name: mycluster-cp-identity
  namespace: org-example
spec:
  name: mycluster-cp-identity
  providerConfigName: example
  location: westeurope
  resourceGroupName: mycluster-rg
  privateDNSZoneID: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.westeurope.azmk8s.io
  virtualNetworkID: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>
  asoPrincipalID: <object ID of the service principal behind the AzureClusterIdentity>
  additionalRoleAssignments:
    # A built-in role, by display name.
    - scope: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<account>
      roleDefinitionName: Storage Blob Data Reader
    # A custom (or built-in) role, by ARM ID.
    - scope: /subscriptions/<sub>/resourceGroups/<rg>
      roleDefinitionId: /subscriptions/<sub>/providers/Microsoft.Authorization/roleDefinitions/<guid>
```

Once the claim is ready, copy `status.identityID` into the cluster's
`global.providerSpecific.controlPlaneIdentity.userAssignedIdentityResourceID`
(with `type: UserAssigned`). Nothing does this automatically yet.

## Additional role assignments

- Each entry needs `scope` and exactly one of `roleDefinitionName` or
  `roleDefinitionId`. At most 20 entries.
- Scope and role are compared case-insensitively, as Azure does. Listing the
  same combination twice is rejected when the claim is applied.
- Assignments are keyed on scope and role, not on their position in the list,
  so reordering the list changes nothing in Azure. Changing an entry's scope or
  role, or switching between name and ID, replaces that assignment.
- Removing an entry, or the claim, deletes the assignment in Azure.
- The service principal behind `providerConfigName` needs
  `Microsoft.Authorization/roleAssignments/write` (e.g. User Access
  Administrator) on every scope listed. Without it the assignment fails and the
  claim stays not Ready; the identity itself is unaffected.

## Testing

`make test-compositions` renders every case under `examples/`. See
`tools/test-compositions.sh` for the layout.
