import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_masked_text2/flutter_masked_text2.dart';
import 'dart:convert';
import 'dart:math';
import '../services/auth_service.dart';
import '../services/permission_service.dart';

class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  final supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();
  List<Map<String, dynamic>> profiles = [];
  bool isLoading = true;
  bool _isCheckingAccess = true;
  String _selectedGenderFilter = 'Todos';
  String _selectedUserTypeFilter = 'Todos';
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  Future<void> _checkAdminAccess() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
        return;
      }
      final response = await supabase
          .from('profiles')
          .select('user_type')
          .eq('id', user.id)
          .maybeSingle();
      final userType = response?['user_type'];
      if (!mounted) return;
      if (userType != 'admin') {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
        return;
      }
      setState(() {
        _isCheckingAccess = false;
      });
      fetchProfiles();
    } catch (e) {
      debugPrint('Erro ao validar acesso aos perfis: $e');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
      }
    }
  }

  Future<void> fetchProfiles() async {
    try {
      setState(() => isLoading = true);
      final response = await supabase
          .from('profiles')
          .select()
          .order('full_name', ascending: true);
      setState(() {
        profiles = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('❌ Erro ao buscar perfis: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> insertProfile(Map<String, dynamic> data) async {
    try {
      await supabase.from('profiles').insert(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Perfil cadastrado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        fetchProfiles();
      }
    } catch (e) {
      debugPrint('❌ Erro ao inserir: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cadastrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> updateProfile(String id, Map<String, dynamic> data) async {
    try {
      data['updated_at'] = DateTime.now().toIso8601String();
      await supabase.from('profiles').update(data).eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Perfil atualizado!'),
            backgroundColor: Colors.green,
          ),
        );
        fetchProfiles();
      }
    } catch (e) {
      debugPrint('❌ Erro ao atualizar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> deleteProfile(String id) async {
    try {
      await supabase.from('profiles').delete().eq('id', id);
      await fetchProfiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Perfil removido!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao deletar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao remover: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void showProfileDialog({Map<String, dynamic>? profile}) {
    showDialog(
      context: context,
      builder: (context) => ProfileFormDialog(
        profile: profile,
        onSave: (data) async {
          if (profile == null) {
            await insertProfile(data);
          } else {
            await updateProfile(profile['id'], data);
          }
        },
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: const Text('Tem certeza que deseja excluir este perfil?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              deleteProfile(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionsDialog(Map<String, dynamic> profile) async {
    final userId = profile['id'];
    final userName = profile['full_name'] ?? 'Usuário';

    final currentPermissions =
        await _permissionService.getUserPermissions(userId);
    final agendaFilters = await _permissionService.getAgendaFilters(userId);

    Map<String, dynamic> financialFilters = {};
    try {
      financialFilters = Map<String, dynamic>.from(
        await (_permissionService as dynamic).getFinancialFilters(userId),
      );
    } catch (_) {
      financialFilters = {};
    }

    final permissionItems = [
      {
        'pageName': 'agenda',
        'title': 'Acesso à Agenda',
        'subtitle': 'Permitir visualizar e usar a agenda',
      },
      {
        'pageName': 'checkin',
        'title': 'Acesso ao Check-in',
        'subtitle': 'Permitir realizar check-in nos eventos',
      },
      {
        'pageName': 'financeiro',
        'title': 'Acesso ao Financeiro',
        'subtitle': 'Permitir visualizar recursos financeiros',
      },
      {
        'pageName': 'treinos',
        'title': 'Acesso aos Treinos',
        'subtitle': 'Permitir visualizar e usar os treinos',
      },
      {
        'pageName': 'campeonatos',
        'title': 'Acesso aos Campeonatos',
        'subtitle': 'Permitir visualizar os campeonatos',
      },
      {
        'pageName': 'perfil',
        'title': 'Acesso ao Perfil',
        'subtitle': 'Permitir visualizar e editar o perfil',
      },
      {
        'pageName': 'birthdays',
        'title': 'Acesso aos Aniversariantes',
        'subtitle': 'Permitir visualizar a página de aniversários',
      },
    ];

    final permissionValues = <String, bool>{
      for (final item in permissionItems)
        item['pageName'] as String:
            currentPermissions[item['pageName']] ?? true,
    };

    bool showMonthFilter = agendaFilters['show_month_filter'] ?? true;
    bool showStatusFilter = agendaFilters['show_status_filter'] ?? true;
    final allowedEventTypes = List<String>.from(
      agendaFilters['allowed_event_types'] ??
          ['treino', 'amistoso', 'campeonato'],
    );
    final allowedConvocationStatuses = List<String>.from(
      agendaFilters['allowed_convocation_statuses'] ??
          ['accepted', 'rejected', 'pending'],
    );
    bool verConvocados = agendaFilters['ver_convocados'] == true;
    bool exportarDadosJogo = agendaFilters['exportar_dados_jogo'] == true;
    final allowedFinancialTypes = List<String>.from(
      financialFilters['allowed_financial_types'] ??
          ['monthly', 'games', 'maintenance', 'other'],
    );

    Future<void> saveAgendaFilters() async {
      await _permissionService.updateAgendaFilters(
        userId: userId,
        showMonthFilter: showMonthFilter,
        showStatusFilter: showStatusFilter,
        allowedEventTypes: allowedEventTypes,
        allowedConvocationStatuses: allowedConvocationStatuses,
      );
    }

    Future<void> saveFinancialFilters() async {
      await (_permissionService as dynamic).updateFinancialFilters(
        userId: userId,
        allowedFinancialTypes: allowedFinancialTypes,
      );
    }

    Future<void> saveAgendaActionPermissions() async {
      await _permissionService.updateAgendaActionPermissions(
        userId: userId,
        verConvocados: verConvocados,
        exportarDadosJogo: exportarDadosJogo,
      );
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: olympusGold),
              const SizedBox(width: 8),
              const Text('Gerenciar Permissões'),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Usuário: $userName',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: olympusBlue,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Permissões de Acesso:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...permissionItems.map((item) {
                    final pageName = item['pageName'] as String;
                    final title = item['title'] as String;
                    final subtitle = item['subtitle'] as String;
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(title),
                      subtitle: Text(subtitle),
                      value: permissionValues[pageName] ?? true,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          await _permissionService.updatePermission(
                            userId: userId,
                            pageName: pageName,
                            canAccess: value,
                          );
                          setDialogState(() {
                            permissionValues[pageName] = value;
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Permissão de ${title.toLowerCase()} ${value ? 'concedida' : 'revogada'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Erro ao atualizar permissão: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    );
                  }).toList(),
                  if (permissionValues['agenda'] == true) ...[
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    const Text(
                      'Filtros da Agenda:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar filtro de mês'),
                      subtitle:
                          const Text('Permitir que o atleta veja o filtro Mês'),
                      value: showMonthFilter,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            showMonthFilter = value;
                          });
                          await saveAgendaFilters();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Filtro de mês ${value ? 'habilitado' : 'desabilitado'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Erro ao atualizar filtro de mês: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tipos de evento permitidos',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        {
                          'value': 'treino',
                          'label': 'Treino',
                        },
                        {
                          'value': 'amistoso',
                          'label': 'Amistoso',
                        },
                        {
                          'value': 'campeonato',
                          'label': 'Campeonatos',
                        },
                      ].map((item) {
                        final value = item['value']!;
                        final selected = allowedEventTypes.contains(value);
                        return FilterChip(
                          label: Text(item['label']!),
                          selected: selected,
                          selectedColor: olympusGold.withOpacity(0.2),
                          checkmarkColor: olympusBlue,
                          onSelected: (enabled) async {
                            final updated =
                                List<String>.from(allowedEventTypes);
                            if (enabled) {
                              if (!updated.contains(value)) {
                                updated.add(value);
                              }
                            } else {
                              updated.remove(value);
                            }
                            if (updated.isEmpty) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Selecione pelo menos um tipo de evento.'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                              return;
                            }
                            try {
                              setDialogState(() {
                                allowedEventTypes
                                  ..clear()
                                  ..addAll(updated);
                              });
                              await saveAgendaFilters();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Erro ao atualizar tipos de evento: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar filtro de status'),
                      subtitle: const Text(
                          'Permitir que o atleta veja o filtro Status da Convocação'),
                      value: showStatusFilter,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            showStatusFilter = value;
                          });
                          await saveAgendaFilters();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Filtro de status ${value ? 'habilitado' : 'desabilitado'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Erro ao atualizar filtro de status: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    if (showStatusFilter) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Status permitidos',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          {
                            'value': 'accepted',
                            'label': 'Aceitou',
                          },
                          {
                            'value': 'rejected',
                            'label': 'Recusou',
                          },
                          {
                            'value': 'pending',
                            'label': 'Pendentes',
                          },
                        ].map((item) {
                          final value = item['value']!;
                          final selected =
                              allowedConvocationStatuses.contains(value);
                          return FilterChip(
                            label: Text(item['label']!),
                            selected: selected,
                            selectedColor: olympusGold.withOpacity(0.2),
                            checkmarkColor: olympusBlue,
                            onSelected: (enabled) async {
                              final updated = List<String>.from(
                                allowedConvocationStatuses,
                              );
                              if (enabled) {
                                if (!updated.contains(value)) {
                                  updated.add(value);
                                }
                              } else {
                                updated.remove(value);
                              }
                              if (updated.isEmpty) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Selecione pelo menos um status de convocação.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                                return;
                              }
                              try {
                                setDialogState(() {
                                  allowedConvocationStatuses
                                    ..clear()
                                    ..addAll(updated);
                                });
                                await saveAgendaFilters();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Erro ao atualizar status permitidos: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                  if (permissionValues['agenda'] == true) ...[
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    const Text(
                      'Opções dos 3 pontinhos na Agenda:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ver convocados'),
                      subtitle: const Text(
                        'Mostrar a opção Ver convocados no perfil do usuário',
                      ),
                      value: verConvocados,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            verConvocados = value;
                          });
                          await saveAgendaActionPermissions();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Opção Ver convocados ${value ? 'habilitada' : 'desabilitada'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao atualizar opção Ver convocados: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Exportar dados do jogo'),
                      subtitle: const Text(
                        'Mostrar a opção Exportar dados do jogo no perfil do usuário',
                      ),
                      value: exportarDadosJogo,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            exportarDadosJogo = value;
                          });
                          await saveAgendaActionPermissions();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Opção Exportar dados do jogo ${value ? 'habilitada' : 'desabilitada'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao atualizar opção Exportar dados do jogo: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                  if (permissionValues['financeiro'] == true) ...[
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    const Text(
                      'Filtros do Financeiro:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tipos financeiros permitidos',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        {
                          'value': 'monthly',
                          'label': 'Mensalidade',
                        },
                        {
                          'value': 'games',
                          'label': 'Jogos',
                        },
                        {
                          'value': 'maintenance',
                          'label': 'Manutenção',
                        },
                        {
                          'value': 'other',
                          'label': 'Outros',
                        },
                      ].map((item) {
                        final value = item['value']!;
                        final selected = allowedFinancialTypes.contains(value);
                        return FilterChip(
                          label: Text(item['label']!),
                          selected: selected,
                          selectedColor: olympusGold.withOpacity(0.2),
                          checkmarkColor: olympusBlue,
                          onSelected: (enabled) async {
                            final updated =
                                List<String>.from(allowedFinancialTypes);
                            if (enabled) {
                              if (!updated.contains(value)) {
                                updated.add(value);
                              }
                            } else {
                              updated.remove(value);
                            }
                            if (updated.isEmpty) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Selecione pelo menos um tipo financeiro.',
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                              return;
                            }
                            try {
                              setDialogState(() {
                                allowedFinancialTypes
                                  ..clear()
                                  ..addAll(updated);
                              });
                              await saveFinancialFilters();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Tipos do financeiro atualizados com sucesso!',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Erro ao atualizar tipos financeiros: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _getCurrentUserType() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;
      final response = await supabase
          .from('profiles')
          .select('user_type')
          .eq('id', user.id)
          .maybeSingle();
      return response?['user_type'];
    } catch (e) {
      debugPrint('Erro ao buscar user_type: $e');
      return null;
    }
  }

  String _getUserTypeLabel(String? userType) {
    switch (userType) {
      case 'admin':
        return 'Administrador';
      case 'coach':
        return 'Técnico';
      case 'athlete':
        return 'Atleta';
      default:
        return 'Membro';
    }
  }

  String _generateRandomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    Random random = Random();
    return List.generate(12, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  void _showPasswordResultDialog(String password, String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: olympusGold, size: 28),
            const SizedBox(width: 12),
            const Text('✅ Usuário Cadastrado!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('E-mail:'),
            Text(email,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: olympusBlue)),
            const SizedBox(height: 10),
            const Text('Senha gerada automaticamente:'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: olympusGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: olympusGold),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      password,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: olympusBlue,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: olympusGold),
                    tooltip: 'Copiar e-mail e senha',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: 'E-mail: $email\nSenha: $password',
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('E-mail e senha copiados!'),
                          duration: Duration(seconds: 2),
                          backgroundColor: olympusBlue,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Envie esta senha para o usuário.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showQuickRegisterDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = MaskedTextController(mask: '(00) 00000-0000');
    String selectedType = 'member';
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person_add_alt_1, color: olympusGold),
              const SizedBox(width: 8),
              const Text('Novo Usuário (Acesso)'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  enabled: !isSubmitting,
                  decoration: InputDecoration(
                    labelText: 'Nome Completo',
                    prefixIcon: const Icon(Icons.person, color: olympusGold),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: olympusGold, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  enabled: !isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: const Icon(Icons.email, color: olympusGold),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: olympusGold, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  enabled: !isSubmitting,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon: const Icon(Icons.phone, color: olympusGold),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: olympusGold, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: InputDecoration(
                    labelText: 'Tipo de Usuário',
                    prefixIcon: const Icon(Icons.badge, color: olympusGold),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: olympusGold, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'member', child: Text('Membro')),
                    DropdownMenuItem(value: 'athlete', child: Text('Atleta')),
                    DropdownMenuItem(value: 'coach', child: Text('Técnico')),
                    DropdownMenuItem(
                        value: 'admin', child: Text('Administrador')),
                  ],
                  onChanged: isSubmitting
                      ? null
                      : (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedType = val;
                            });
                          }
                        },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  isSubmitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Preencha nome e e-mail'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      final password = _generateRandomPassword();
                      final email = emailCtrl.text.trim();
                      final adminRefreshToken =
                          supabase.auth.currentSession?.refreshToken;
                      final adminUserId = supabase.auth.currentUser?.id;

                      setDialogState(() {
                        isSubmitting = true;
                      });

                      try {
                        final response = await supabase.auth.signUp(
                          email: email,
                          password: password,
                        );

                        if (response.user == null) {
                          throw Exception('Usuário não foi criado.');
                        }

                        if (adminRefreshToken != null) {
                          await supabase.auth.setSession(adminRefreshToken);
                          await Future.delayed(
                            const Duration(milliseconds: 300),
                          );
                        }

                        if (adminUserId != null &&
                            supabase.auth.currentUser?.id != adminUserId) {
                          throw Exception(
                            'Não foi possível restaurar a sessão do administrador.',
                          );
                        }

                        final userId = response.user!.id;

                        await Future.delayed(const Duration(milliseconds: 500));

                        await supabase.from('profiles').update({
                          'full_name': nameCtrl.text.trim(),
                          'phone': phoneCtrl.text.replaceAll(RegExp(r'\D'), ''),
                          'user_type': selectedType,
                          'updated_at': DateTime.now().toIso8601String(),
                        }).eq('id', userId);

                        if (!mounted) return;

                        Navigator.pop(dialogContext);
                        _showPasswordResultDialog(password, email);
                        fetchProfiles();
                      } catch (e) {
                        debugPrint('❌ Erro ao cadastrar: $e');

                        if (adminRefreshToken != null) {
                          try {
                            await supabase.auth.setSession(adminRefreshToken);
                          } catch (restoreError) {
                            debugPrint(
                              '❌ Erro ao restaurar sessão do admin: $restoreError',
                            );
                          }
                        }

                        if (!mounted) return;

                        String errorMessage = 'Erro ao cadastrar';
                        if (e.toString().contains('Database error')) {
                          errorMessage =
                              'Erro no banco. Verifique se o trigger está configurado corretamente.';
                        } else if (e
                            .toString()
                            .contains('User already registered')) {
                          errorMessage = 'E-mail já cadastrado.';
                        } else if (e.toString().contains(
                            'Não foi possível restaurar a sessão do administrador')) {
                          errorMessage =
                              'Usuário criado, mas a sessão do admin não foi restaurada corretamente.';
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errorMessage),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (mounted) {
                          setDialogState(() {
                            isSubmitting = false;
                          });
                        }
                      }
                    },
              icon: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(olympusBlue),
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(isSubmitting ? 'Cadastrando...' : 'Cadastrar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusGold,
                foregroundColor: olympusBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredProfiles() {
    final filtered = profiles.where((profile) {
      final gender = (profile['gender'] ?? '').toString().trim();
      final userType = (profile['user_type'] ?? '').toString().trim();

      final matchesGender =
          _selectedGenderFilter == 'Todos' || gender == _selectedGenderFilter;
      final matchesUserType = _selectedUserTypeFilter == 'Todos' ||
          userType == _selectedUserTypeFilter;

      return matchesGender && matchesUserType;
    }).toList();

    filtered.sort((a, b) {
      final nameA = (a['full_name'] ?? '').toString().trim().toLowerCase();
      final nameB = (b['full_name'] ?? '').toString().trim().toLowerCase();
      return nameA.compareTo(nameB);
    });

    return filtered;
  }

  String _getSelectedFiltersLabel() {
    if (_selectedGenderFilter == 'Todos' &&
        _selectedUserTypeFilter == 'Todos') {
      return 'Todos os perfis';
    }
    if (_selectedGenderFilter != 'Todos' &&
        _selectedUserTypeFilter != 'Todos') {
      return '${_getTypeLabel(_selectedUserTypeFilter)} • $_selectedGenderFilter';
    }
    if (_selectedUserTypeFilter != 'Todos') {
      return _getTypeLabel(_selectedUserTypeFilter);
    }
    return _selectedGenderFilter;
  }

  Widget _buildFilterDropdown({
    required IconData icon,
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withOpacity(0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: olympusGold, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: value,
              iconEnabledColor: olympusGold,
              dropdownColor: olympusBlue.withOpacity(0.96),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white.withOpacity(0.10),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: olympusGold, width: 1.8),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              items: items,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersBar(int resultsCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              _buildFilterDropdown(
                icon: Icons.filter_alt_outlined,
                label: 'Gênero',
                value: _selectedGenderFilter,
                items: const [
                  DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                  DropdownMenuItem(
                      value: 'Masculino', child: Text('Masculino')),
                  DropdownMenuItem(value: 'Feminino', child: Text('Feminino')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedGenderFilter = value;
                  });
                },
              ),
              const SizedBox(width: 10),
              _buildFilterDropdown(
                icon: Icons.badge_outlined,
                label: 'Tipo de usuário',
                value: _selectedUserTypeFilter,
                items: const [
                  DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                  DropdownMenuItem(value: 'member', child: Text('Membro')),
                  DropdownMenuItem(value: 'athlete', child: Text('Atleta')),
                  DropdownMenuItem(value: 'coach', child: Text('Técnico')),
                  DropdownMenuItem(
                      value: 'admin', child: Text('Administrador')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedUserTypeFilter = value;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.14),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.people_alt_outlined, color: olympusGold, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getSelectedFiltersLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: olympusGold.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: olympusGold.withOpacity(0.28),
                    ),
                  ),
                  child: Text(
                    '$resultsCount resultado${resultsCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> profile) {
    final avatarUrl = profile['avatar_url'];
    final userType = (profile['user_type'] ?? '').toString();
    final phone = (profile['phone'] ?? '').toString();
    final cpf = (profile['cpf'] ?? '').toString();
    final gender = (profile['gender'] ?? '').toString();

    Color cardColor;
    if (gender == 'Masculino') {
      cardColor = Colors.blue;
    } else if (gender == 'Feminino') {
      cardColor = Colors.purple;
    } else {
      cardColor = Colors.white;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cardColor.withOpacity(0.25),
                  cardColor.withOpacity(0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: cardColor.withOpacity(0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => showProfileDialog(profile: profile),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _getColorForType(userType).withOpacity(0.35),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor:
                            _getColorForType(userType).withOpacity(0.16),
                        backgroundImage:
                            avatarUrl != null && avatarUrl.toString().isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                        child: avatarUrl == null || avatarUrl.toString().isEmpty
                            ? Text(
                                profile['full_name']?[0]?.toUpperCase() ?? '?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile['full_name'] ?? 'Sem nome',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontSize: 21,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _getColorForType(userType)
                                      .withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _getColorForType(userType)
                                        .withOpacity(0.20),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.badge_outlined,
                                      size: 14,
                                      color: _getColorForType(userType),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _getTypeLabel(userType),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (gender.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cardColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: cardColor.withOpacity(0.25),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.wc,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        gender,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (phone.isNotEmpty)
                            _buildProfileInfoLine(
                              icon: Icons.phone_outlined,
                              text: _formatPhone(phone),
                            ),
                          if (cpf.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: _buildProfileInfoLine(
                                icon: Icons.credit_card_outlined,
                                text: 'CPF: ${_formatCpf(cpf)}',
                              ),
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: olympusGold),
                      onSelected: (value) {
                        if (value == 'edit') {
                          showProfileDialog(profile: profile);
                        } else if (value == 'delete') {
                          _confirmDelete(profile['id']);
                        } else if (value == 'permissions') {
                          _showPermissionsDialog(profile);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Editar'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Excluir'),
                        ),
                        PopupMenuItem(
                          value: 'permissions',
                          child: Text('Permissões'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfoLine({
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: olympusGold),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.white.withOpacity(0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.14),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.56),
                  olympusLightBlue.withOpacity(0.26),
                  Colors.black.withOpacity(0.62),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.78),
                radius: 1.08,
                colors: [
                  olympusGold.withOpacity(0.12),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassContentShell({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final horizontal = isCompact ? 10.0 : 14.0;
        final top = isCompact ? 10.0 : 14.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.14),
                      Colors.white.withOpacity(0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.20),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfilesEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            'Nenhum perfil encontrado para os filtros selecionados',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.92),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredProfiles = _getFilteredProfiles();

    if (_isCheckingAccess) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Perfis - Olympus Voleibol',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            FutureBuilder<String?>(
              future: _getCurrentUserType(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Text(
                    '👤 ${_getUserTypeLabel(snapshot.data)}',
                    style: TextStyle(
                        fontSize: 12, color: olympusGold.withOpacity(0.9)),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        centerTitle: false,
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Cadastrar Usuário (Login)',
            onPressed: _showQuickRegisterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              final authService = AuthService();
              await authService.signOut();
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchProfiles,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(olympusGold),
                  ),
                )
              : _buildGlassContentShell(
                  child: Column(
                    children: [
                      _buildFiltersBar(filteredProfiles.length),
                      Expanded(
                        child: filteredProfiles.isEmpty
                            ? _buildProfilesEmptyState()
                            : ListView.builder(
                                itemCount: filteredProfiles.length,
                                padding: const EdgeInsets.all(8),
                                itemBuilder: (context, index) {
                                  final profile = filteredProfiles[index];
                                  return _buildProfileCard(profile);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showProfileDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Novo Perfil'),
        backgroundColor: olympusGold,
        foregroundColor: olympusBlue,
        elevation: 4,
      ),
    );
  }

  String _formatCpf(String? cpf) {
    if (cpf == null) return '';
    final numbers = cpf.toString().replaceAll(RegExp(r'\D'), '');
    if (numbers.length != 11) return cpf.toString();
    return '${numbers.substring(0, 3)}.${numbers.substring(3, 6)}.${numbers.substring(6, 9)}-${numbers.substring(9)}';
  }

  String _formatPhone(String? phone) {
    if (phone == null) return '';
    final numbers = phone.toString().replaceAll(RegExp(r'\D'), '');
    if (numbers.length == 11) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 7)}-${numbers.substring(7)}';
    } else if (numbers.length == 10) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 6)}-${numbers.substring(6)}';
    }
    return phone.toString();
  }

  Color _getColorForType(String? type) {
    switch (type) {
      case 'athlete':
        return olympusGold;
      case 'coach':
        return olympusLightBlue;
      case 'admin':
        return Colors.red[700]!;
      default:
        return olympusBlue;
    }
  }

  String _getTypeLabel(String? type) {
    switch (type) {
      case 'athlete':
        return 'Atleta';
      case 'coach':
        return 'Técnico';
      case 'admin':
        return 'Administrador';
      default:
        return 'Membro';
    }
  }
}

class ProfileFormDialog extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final Future<void> Function(Map<String, dynamic> data) onSave;
  const ProfileFormDialog({
    super.key,
    this.profile,
    required this.onSave,
  });

  @override
  State<ProfileFormDialog> createState() => _ProfileFormDialogState();
}

class _ProfileFormDialogState extends State<ProfileFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late TextEditingController _fullNameController;
  late MaskedTextController _phoneController;
  late TextEditingController _birthDateController;
  late MaskedTextController _rgController;
  late MaskedTextController _cpfController;
  late MaskedTextController _zipCodeController;
  late TextEditingController _streetController;
  late TextEditingController _streetNumberController;
  late TextEditingController _complementController;
  late TextEditingController _neighborhoodController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _avatarUrlController;
  String _selectedUserType = 'member';
  String _selectedGender = '';
  String _selectedPosition = '';
  XFile? _selectedImage;
  bool _isLoading = false;
  bool _isFetchingCep = false;
  bool _isUploading = false;
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  final Map<String, List<Map<String, String>>> _positions = {
    'Masculino': [
      {'value': 'Ponteiro', 'label': 'Ponteiro'},
      {'value': 'Levantador', 'label': 'Levantador'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposto', 'label': 'Oposto'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
    'Feminino': [
      {'value': 'Ponteira', 'label': 'Ponteira'},
      {'value': 'Levantadora', 'label': 'Levantadora'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposta', 'label': 'Oposta'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _fullNameController =
        TextEditingController(text: widget.profile?['full_name'] ?? '');
    _phoneController = MaskedTextController(
        mask: '(00) 00000-0000', text: widget.profile?['phone'] ?? '');
    _birthDateController =
        TextEditingController(text: widget.profile?['birth_date'] ?? '');
    _rgController = MaskedTextController(
        mask: '00.000.000-0', text: widget.profile?['rg'] ?? '');
    _cpfController = MaskedTextController(
        mask: '000.000.000-00', text: widget.profile?['cpf'] ?? '');
    _zipCodeController = MaskedTextController(
        mask: '00000-000', text: widget.profile?['zip_code'] ?? '');
    _streetController =
        TextEditingController(text: widget.profile?['street'] ?? '');
    _streetNumberController =
        TextEditingController(text: widget.profile?['street_number'] ?? '');
    _complementController =
        TextEditingController(text: widget.profile?['complement'] ?? '');
    _neighborhoodController =
        TextEditingController(text: widget.profile?['neighborhood'] ?? '');
    _cityController =
        TextEditingController(text: widget.profile?['city'] ?? '');
    _stateController =
        TextEditingController(text: widget.profile?['state'] ?? '');
    _avatarUrlController =
        TextEditingController(text: widget.profile?['avatar_url'] ?? '');
    _selectedUserType = widget.profile?['user_type'] ?? 'member';
    _selectedGender = widget.profile?['gender'] ?? '';
    _selectedPosition = widget.profile?['court_position'] ?? '';
    _zipCodeController.addListener(_onZipCodeChanged);
  }

  void _onZipCodeChanged() {
    final cep = _zipCodeController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length == 8 && !_isFetchingCep) {
      _fetchAddressByCep(cep);
    }
  }

  Future<void> _fetchAddressByCep(String cep) async {
    setState(() => _isFetchingCep = true);
    try {
      final response =
          await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['erro'] == null && mounted) {
          setState(() {
            _streetController.text = data['logradouro'] ?? '';
            _neighborhoodController.text = data['bairro'] ?? '';
            _cityController.text = data['localidade'] ?? '';
            _stateController.text = data['uf'] ?? '';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Endereço preenchido automaticamente!'),
              duration: Duration(seconds: 2),
              backgroundColor: olympusBlue,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingCep = false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao selecionar imagem'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;
    if (mounted) {
      setState(() => _isUploading = true);
    }
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_fullNameController.text.replaceAll(RegExp(r"\D"), "")}.jpg';
      final supabase = Supabase.instance.client;
      final Uint8List? fileBytes = await _selectedImage!.readAsBytes();
      if (fileBytes == null) return null;
      await supabase.storage.from('avatars').uploadBinary(fileName, fileBytes,
          fileOptions: const FileOptions(upsert: true));
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('Erro ao fazer upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: olympusGold,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  String _removeMask(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.replaceAll(RegExp(r'\D'), '');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.profile == null ? 'Novo Perfil' : 'Editar Perfil'),
          backgroundColor: olympusBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _buildFormContent(context),
      );
    }
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 600),
        child: _buildFormContent(context),
      ),
    );
  }

  Widget _buildFormContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (MediaQuery.of(context).size.width >= 600)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [olympusBlue, olympusLightBlue],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.person, color: olympusGold, size: 28),
                const SizedBox(width: 12),
                Text(
                  widget.profile == null ? 'Novo Perfil' : 'Editar Perfil',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: olympusGold.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: olympusGold, width: 3),
                        ),
                        child: ClipOval(
                          child: _getAvatarImage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_camera, color: olympusGold),
                      label: const Text(
                        'Selecionar Foto',
                        style: TextStyle(color: olympusBlue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      labelText: 'Nome Completo *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person, color: olympusGold),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedUserType,
                    decoration: InputDecoration(
                      labelText: 'Tipo de Usuário *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.badge, color: olympusGold),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'member', child: Text('Membro')),
                      DropdownMenuItem(value: 'athlete', child: Text('Atleta')),
                      DropdownMenuItem(value: 'coach', child: Text('Técnico')),
                      DropdownMenuItem(
                          value: 'admin', child: Text('Administrador')),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedUserType = value!),
                    validator: (value) =>
                        value == null ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cpfController,
                          decoration: InputDecoration(
                            labelText: 'CPF *',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.credit_card,
                                color: olympusGold),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) => _removeMask(value).length != 11
                              ? 'CPF inválido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _rgController,
                          decoration: InputDecoration(
                            labelText: 'RG *',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.credit_card,
                                color: olympusGold),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: 'Telefone *',
                            border: const OutlineInputBorder(),
                            prefixIcon:
                                const Icon(Icons.phone, color: olympusGold),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          keyboardType: TextInputType.phone,
                          validator: (value) => _removeMask(value).length < 10
                              ? 'Telefone inválido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedGender.isNotEmpty
                              ? _selectedGender
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Gênero *',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.transgender,
                                color: olympusGold),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'Masculino', child: Text('Masculino')),
                            DropdownMenuItem(
                                value: 'Feminino', child: Text('Feminino')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedGender = value ?? '';
                              _selectedPosition = '';
                            });
                          },
                          validator: (value) =>
                              value == null ? 'Campo obrigatório' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _birthDateController,
                    decoration: InputDecoration(
                      labelText: 'Data de Nascimento',
                      border: const OutlineInputBorder(),
                      prefixIcon:
                          const Icon(Icons.calendar_today, color: olympusGold),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today,
                            color: olympusGold),
                        onPressed: _selectDate,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    readOnly: true,
                  ),
                  const SizedBox(height: 12),
                  if (_selectedUserType == 'athlete' &&
                      _selectedGender.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: _selectedPosition.isNotEmpty
                          ? _selectedPosition
                          : null,
                      decoration: InputDecoration(
                        labelText: 'Posição na Quadra',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.sports_volleyball,
                            color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      items: _positions[_selectedGender]!
                          .map((pos) => DropdownMenuItem(
                                value: pos['value'],
                                child: Text(pos['label']!),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedPosition = value ?? ''),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: olympusGold, size: 20),
                      const SizedBox(width: 8),
                      const Text('Endereço',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: olympusBlue,
                          )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _zipCodeController,
                    decoration: InputDecoration(
                      labelText: 'CEP *',
                      border: const OutlineInputBorder(),
                      prefixIcon:
                          const Icon(Icons.location_on, color: olympusGold),
                      suffixIcon: _isFetchingCep
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(olympusGold),
                              ),
                            )
                          : null,
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 9,
                    validator: (value) =>
                        _removeMask(value).length != 8 ? 'CEP inválido' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _streetController,
                          decoration: InputDecoration(
                            labelText: 'Rua *',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _streetNumberController,
                          decoration: InputDecoration(
                            labelText: 'Número *',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _complementController,
                    decoration: InputDecoration(
                      labelText: 'Complemento',
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _neighborhoodController,
                    decoration: InputDecoration(
                      labelText: 'Bairro *',
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _cityController,
                          decoration: InputDecoration(
                            labelText: 'Cidade *',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _stateController,
                          decoration: InputDecoration(
                            labelText: 'Estado *',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          maxLength: 2,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: MediaQuery.of(context).size.width >= 600
                ? const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading || _isUploading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: olympusGold,
                  foregroundColor: olympusBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading || _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(olympusBlue),
                        ),
                      )
                    : Text(
                        widget.profile == null ? 'Cadastrar' : 'Salvar',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _getAvatarImage() {
    if (_selectedImage != null) {
      return FutureBuilder<Uint8List?>(
        future: _selectedImage!.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          }
          return const Icon(Icons.person, size: 60, color: Colors.grey);
        },
      );
    }
    if (widget.profile?['avatar_url'] != null &&
        widget.profile!['avatar_url'].toString().isNotEmpty) {
      return Image.network(
        widget.profile!['avatar_url'],
        fit: BoxFit.cover,
        errorBuilder: (c, o, s) =>
            const Icon(Icons.person, size: 60, color: Colors.grey),
      );
    }
    return const Icon(Icons.person, size: 60, color: Colors.grey);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    String? avatarUrl = _avatarUrlController.text.trim();
    if (_selectedImage != null) {
      final uploadedUrl = await _uploadImage();
      if (uploadedUrl != null) {
        avatarUrl = uploadedUrl;
      }
    }
    if (!mounted) return;
    final data = <String, dynamic>{
      'full_name': _fullNameController.text.trim(),
      'user_type': _selectedUserType,
      'phone': _removeMask(_phoneController.text),
      if (_birthDateController.text.isNotEmpty)
        'birth_date': _birthDateController.text,
      'rg': _removeMask(_rgController.text),
      'cpf': _removeMask(_cpfController.text),
      'gender': _selectedGender,
      if (_selectedPosition.isNotEmpty) 'court_position': _selectedPosition,
      'zip_code': _removeMask(_zipCodeController.text),
      'street': _streetController.text.trim(),
      'street_number': _streetNumberController.text.trim(),
      'complement': _complementController.text.trim(),
      'neighborhood': _neighborhoodController.text.trim(),
      'city': _cityController.text.trim(),
      'state': _stateController.text.trim().toUpperCase(),
      if (avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
    };
    await widget.onSave(data);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _zipCodeController.removeListener(_onZipCodeChanged);
    _fullNameController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _rgController.dispose();
    _cpfController.dispose();
    _zipCodeController.dispose();
    _streetController.dispose();
    _streetNumberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }
}
