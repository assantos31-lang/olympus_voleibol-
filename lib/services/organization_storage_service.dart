import 'organization_context_service.dart';

class OrganizationStorageService {
  OrganizationStorageService._();

  static String scopedPath(String relativePath) {
    final cleaned = relativePath.replaceFirst(RegExp(r'^/+'), '');
    if (cleaned.startsWith('organizations/')) return cleaned;
    final organizationId = OrganizationContextService.instance.currentId;
    return 'organizations/$organizationId/$cleaned';
  }

  static String organizationRoot() {
    return 'organizations/${OrganizationContextService.instance.currentId}';
  }
}
