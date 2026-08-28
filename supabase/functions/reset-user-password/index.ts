import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

function response(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {...corsHeaders, 'Content-Type': 'application/json'},
  })
}

function generateTemporaryPassword() {
  const groups = [
    'ABCDEFGHJKLMNPQRSTUVWXYZ',
    'abcdefghijkmnopqrstuvwxyz',
    '23456789',
    '!@#$%&*',
  ]
  const randomIndex = (length: number) => {
    const value = new Uint32Array(1)
    crypto.getRandomValues(value)
    return value[0] % length
  }
  const characters = groups.map((group) => group[randomIndex(group.length)])
  const all = groups.join('')
  while (characters.length < 12) {
    characters.push(all[randomIndex(all.length)])
  }
  for (let index = characters.length - 1; index > 0; index--) {
    const target = randomIndex(index + 1)
    ;[characters[index], characters[target]] = [characters[target], characters[index]]
  }
  return characters.join('')
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders})
  }
  if (request.method !== 'POST') {
    return response(405, {error: 'Metodo nao permitido.'})
  }

  const authorization = request.headers.get('Authorization') ?? ''
  if (!authorization.startsWith('Bearer ')) {
    return response(401, {error: 'Sessao administrativa ausente.'})
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return response(500, {error: 'Configuracao segura do Supabase ausente.'})
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: {headers: {Authorization: authorization}},
    auth: {persistSession: false, autoRefreshToken: false},
  })
  const {data: callerData, error: callerError} =
    await callerClient.auth.getUser()
  if (callerError || !callerData.user) {
    return response(401, {error: 'Sessao expirada. Entre novamente.'})
  }

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch (_) {
    return response(400, {error: 'Dados invalidos.'})
  }
  const targetUserId = String(body.user_id ?? '').trim()
  if (!/^[0-9a-f-]{36}$/i.test(targetUserId)) {
    return response(400, {error: 'Usuario invalido.'})
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {persistSession: false, autoRefreshToken: false},
  })
  const {data: targetProfile, error: profileError} = await adminClient
    .from('profiles')
    .select('id, organization_id')
    .eq('id', targetUserId)
    .maybeSingle()
  if (profileError || !targetProfile) {
    return response(404, {error: 'Perfil do usuario nao encontrado.'})
  }

  const {data: isPlatformAdmin} =
    await callerClient.rpc('is_platform_admin_v1')
  const {data: isOrganizationAdmin} = await callerClient.rpc(
    'is_organization_admin',
    {target_organization: targetProfile.organization_id},
  )
  if (isPlatformAdmin !== true && isOrganizationAdmin !== true) {
    return response(403, {
      error: 'Voce nao pode redefinir a senha de usuarios de outro clube.',
    })
  }

  const {data: targetAuth, error: targetAuthError} =
    await adminClient.auth.admin.getUserById(targetUserId)
  if (targetAuthError || !targetAuth.user) {
    return response(404, {error: 'Conta de acesso nao encontrada.'})
  }

  const password = generateTemporaryPassword()
  const metadata = targetAuth.user.user_metadata ?? {}
  const {error: updateError} = await adminClient.auth.admin.updateUserById(
    targetUserId,
    {
      password,
      user_metadata: {
        ...metadata,
        must_change_password: true,
        password_reset_by_admin_at: new Date().toISOString(),
      },
    },
  )
  if (updateError) {
    return response(500, {error: updateError.message})
  }

  return response(200, {
    success: true,
    user_id: targetUserId,
    password,
    must_change_password: true,
  })
})
