import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

function respond(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {...corsHeaders, 'Content-Type': 'application/json'},
  })
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value)
}

async function removeOwnedFiles(
  adminClient: ReturnType<typeof createClient>,
  userId: string,
) {
  const {data, error} = await adminClient.rpc(
    'list_user_owned_storage_objects_v1',
    {p_user_id: userId},
  )
  if (error) throw new Error(`Falha ao localizar arquivos: ${error.message}`)

  const filesByBucket = new Map<string, string[]>()
  for (const item of data ?? []) {
    const bucketId = String(item.bucket_id ?? '').trim()
    const objectName = String(item.object_name ?? '').trim()
    if (!bucketId || !objectName) continue
    const files = filesByBucket.get(bucketId) ?? []
    files.push(objectName)
    filesByBucket.set(bucketId, files)
  }

  let removedFiles = 0
  for (const [bucketId, files] of filesByBucket.entries()) {
    for (let index = 0; index < files.length; index += 1000) {
      const batch = files.slice(index, index + 1000)
      const {error: removeError} = await adminClient.storage
        .from(bucketId)
        .remove(batch)
      if (removeError) {
        throw new Error(`Falha ao remover arquivos: ${removeError.message}`)
      }
      removedFiles += batch.length
    }
  }
  return removedFiles
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders})
  }
  if (request.method !== 'POST') {
    return respond(405, {error: 'Método não permitido.'})
  }

  const authorization = request.headers.get('Authorization') ?? ''
  if (!authorization.startsWith('Bearer ')) {
    return respond(401, {error: 'Sessão administrativa ausente.'})
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return respond(500, {error: 'Configuração segura indisponível.'})
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: {headers: {Authorization: authorization}},
    auth: {persistSession: false, autoRefreshToken: false},
  })
  const {data: callerData, error: callerError} =
    await callerClient.auth.getUser()
  if (callerError || !callerData.user) {
    return respond(401, {error: 'Sessão expirada. Entre novamente.'})
  }

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch (_) {
    return respond(400, {error: 'Dados de confirmação inválidos.'})
  }

  const targetUserId = String(body.user_id ?? '').trim()
  const confirmationEmail = String(body.confirmation_email ?? '')
    .trim()
    .toLowerCase()
  if (!isUuid(targetUserId)) {
    return respond(400, {error: 'Usuário inválido.'})
  }
  const isSelfDeletion = targetUserId === callerData.user.id

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {persistSession: false, autoRefreshToken: false},
  })
  const {data: targetProfile, error: profileError} = await adminClient
    .from('profiles')
    .select('id, organization_id, full_name')
    .eq('id', targetUserId)
    .maybeSingle()
  if (profileError || !targetProfile) {
    return respond(404, {error: 'Perfil do usuário não encontrado.'})
  }

  const {data: isPlatformAdmin} = await callerClient.rpc(
    'is_platform_admin_v1',
  )
  const {data: isOrganizationAdmin} = isSelfDeletion
    ? {data: false}
    : await callerClient.rpc('is_organization_admin', {
      target_organization: targetProfile.organization_id,
    })
  if (
    !isSelfDeletion &&
    isPlatformAdmin !== true &&
    isOrganizationAdmin !== true
  ) {
    return respond(403, {
      error: 'Você não pode excluir usuários de outro clube.',
    })
  }

  const {data: targetAuth, error: authLookupError} =
    await adminClient.auth.admin.getUserById(targetUserId)
  if (authLookupError || !targetAuth.user) {
    return respond(404, {error: 'Conta de autenticação não encontrada.'})
  }
  const targetEmail = (targetAuth.user.email ?? '').trim().toLowerCase()
  if (!targetEmail || confirmationEmail !== targetEmail) {
    return respond(400, {
      error: 'O e-mail de confirmação não corresponde ao usuário.',
    })
  }

  if (isPlatformAdmin !== true) {
    const {data: targetMembership} = await adminClient
      .from('organization_members')
      .select('role')
      .eq('organization_id', targetProfile.organization_id)
      .eq('user_id', targetUserId)
      .maybeSingle()
    if (targetMembership?.role === 'owner') {
      return respond(403, {
        error: isSelfDeletion
          ? 'Transfira a propriedade do clube antes de excluir sua conta.'
          : 'Somente o administrador da plataforma pode excluir o proprietário do clube.',
      })
    }
  }

  try {
    const removedFiles = await removeOwnedFiles(adminClient, targetUserId)
    const {error: deleteError} = await adminClient.auth.admin.deleteUser(
      targetUserId,
      false,
    )
    if (deleteError) throw new Error(deleteError.message)

    // Compatibilidade para cadastros antigos que ainda não usam FK cascade.
    const {error: legacyProfileError} = await adminClient
      .from('profiles')
      .delete()
      .eq('id', targetUserId)
    if (legacyProfileError) {
      throw new Error(
        `A conta de acesso foi removida, mas a limpeza do perfil falhou: ${legacyProfileError.message}`,
      )
    }

    return respond(200, {
      success: true,
      removed_files: removedFiles,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    return respond(500, {
      error: `Não foi possível concluir a exclusão: ${message}`,
    })
  }
})
