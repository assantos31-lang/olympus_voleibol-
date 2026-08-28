import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

function json(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {...corsHeaders, 'Content-Type': 'application/json'},
  })
}

function normalizedRole(value: unknown) {
  const role = String(value ?? '').trim().toLowerCase()
  if (role === 'admin' || role === 'coach' || role === 'athlete') return role
  return 'member'
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', {headers: corsHeaders})
  if (request.method !== 'POST') return json(405, {error: 'Método não permitido.'})

  const authorization = request.headers.get('Authorization') ?? ''
  if (!authorization.startsWith('Bearer ')) {
    return json(401, {error: 'Sessão administrativa ausente.'})
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json(500, {error: 'Configuração segura do Supabase ausente.'})
  }

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch (_) {
    return json(400, {error: 'Dados inválidos.'})
  }

  const organizationId = String(body.organization_id ?? '').trim()
  const email = String(body.email ?? '').trim().toLowerCase()
  const password = String(body.password ?? '')
  const fullName = String(body.full_name ?? '').trim()
  const phone = String(body.phone ?? '').replace(/\D/g, '')
  const role = normalizedRole(body.user_type)

  if (!/^[0-9a-f-]{36}$/i.test(organizationId)) {
    return json(400, {error: 'Clube inválido.'})
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json(400, {error: 'E-mail inválido.'})
  }
  if (fullName.length < 3) return json(400, {error: 'Informe o nome completo.'})
  if (password.length < 8 || !/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
    return json(400, {error: 'A senha precisa ter 8 caracteres, com letra e número.'})
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: {headers: {Authorization: authorization}},
    auth: {persistSession: false, autoRefreshToken: false},
  })
  const {data: caller, error: callerError} = await callerClient.auth.getUser()
  if (callerError || !caller.user) return json(401, {error: 'Sessão expirada. Entre novamente.'})

  const {data: allowed, error: permissionError} = await callerClient
    .rpc('is_organization_admin', {target_organization: organizationId})
  if (permissionError || allowed !== true) {
    return json(403, {error: 'Somente o administrador deste clube pode cadastrar usuários.'})
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {persistSession: false, autoRefreshToken: false},
  })
  const {data: organization} = await admin
    .from('organizations')
    .select('id, is_active')
    .eq('id', organizationId)
    .maybeSingle()
  if (!organization || organization.is_active === false) {
    return json(409, {error: 'O clube está inativo ou não existe.'})
  }

  const {data: created, error: createError} = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      full_name: fullName,
      user_type: role,
      organization_id: organizationId,
      must_change_password: true,
      must_complete_profile: true,
    },
  })
  if (createError || !created.user) {
    const duplicate = createError?.message.toLowerCase().includes('already')
    return json(duplicate ? 409 : 500, {
      error: duplicate ? 'Este e-mail já possui conta no aplicativo.' :
        (createError?.message ?? 'Não foi possível criar a conta.'),
    })
  }

  const userId = created.user.id
  try {
    const {error: profileError} = await admin.from('profiles').update({
      organization_id: organizationId,
      full_name: fullName,
      phone,
      user_type: role,
      is_active: true,
      updated_at: new Date().toISOString(),
    }).eq('id', userId)
    if (profileError) throw profileError

    await admin.from('user_profiles').update({organization_id: organizationId})
      .eq('id', userId)
    await admin.from('organization_members').delete().eq('user_id', userId)
      .neq('organization_id', organizationId)
    const {error: memberError} = await admin.from('organization_members').upsert({
      organization_id: organizationId,
      user_id: userId,
      role,
      status: 'active',
      is_default: true,
      updated_at: new Date().toISOString(),
    }, {onConflict: 'organization_id,user_id'})
    if (memberError) throw memberError

    const {error: roleError} = await admin.from('user_roles').insert({
      user_id: userId,
      role,
      is_active: true,
      organization_id: organizationId,
      updated_at: new Date().toISOString(),
    })
    if (roleError) throw roleError
  } catch (error) {
    await admin.auth.admin.deleteUser(userId)
    console.error('Falha ao vincular usuário ao clube', error)
    return json(500, {error: 'A conta não foi criada porque não foi possível vinculá-la ao clube.'})
  }

  return json(200, {success: true, user_id: userId, organization_id: organizationId, email})
})
