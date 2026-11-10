# AKSControlPlaneIdentity

Creates the user-assigned identity a private AKS cluster with a BYO private DNS
zone needs for its control plane, plus the role assignments that go with it:

| Role                             | Principal                | Scope                        |
|----------------------------------|--------------------------|------------------------------|
| Private DNS Zone Contributor     | control-plane identity   | `spec.privateDNSZoneID`      |
| Network Contributor              | control-plane identity   | `spec.virtualNetworkID`      |
| Managed Identity Operator        | `spec.asoPrincipalID`    | the control-plane identity   |
| `spec.additionalRoleAssignments` | control-plane identity   | per entry                    |

## Usage

```yaml
apiVersion: crossplane.giantswarm.io/v1alpha1
kind: AKSControlPlaneIdentity
metadata:
  name: mycluster-controlplane
  namespace: org-example
spec:
  name: mycluster-controlplane
  providerConfigName: example
  location: westeurope
  resourceGroupName: mycluster
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

The identity's resource ID is known before it is provisioned, so the cluster
can reference it in the same manifest as the claim:

```
/subscriptions/<sub>/resourceGroups/<spec.resourceGroupName>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<spec.name>
```

For the claim above, that gives these cluster values:

```yaml
global:
  providerSpecific:
    controlPlaneIdentity:
      type: UserAssigned
      userAssignedIdentityResourceID: /subscriptions/<sub>/resourceGroups/mycluster/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mycluster-controlplane
```

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
