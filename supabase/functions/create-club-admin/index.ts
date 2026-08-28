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
  const {data: userData, error: userError} = await callerClient.auth.getUser()
  if (userError || !userData.user) {
    return response(401, {error: 'Sessao expirada. Entre novamente.'})
  }

  const {data: isPlatformAdmin, error: permissionError} =
    await callerClient.rpc('is_platform_admin_v1')
  if (permissionError || isPlatformAdmin !== true) {
    return response(403, {error: 'Acesso restrito ao Admin Master.'})
  }

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch (_) {
    return response(400, {error: 'Dados invalidos.'})
  }

  const organizationId = String(body.organization_id ?? '').trim()
  const email = String(body.email ?? '').trim().toLowerCase()
  const password = String(body.password ?? '')
  if (!/^[0-9a-f-]{36}$/i.test(organizationId)) {
    return response(400, {error: 'Clube invalido.'})
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return response(400, {error: 'E-mail invalido.'})
  }
  if (password.length < 8 || !/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
    return response(400, {
      error: 'A senha deve ter 8 caracteres, incluindo letra e numero.',
    })
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {persistSession: false, autoRefreshToken: false},
  })
  const {data: invitation, error: invitationError} = await adminClient
    .from('organization_admin_invitations')
    .select('id, organization_id, email, status, expires_at')
    .eq('organization_id', organizationId)
    .eq('email_normalized', email)
    .eq('status', 'pending')
    .maybeSingle()

  if (invitationError) {
    return response(500, {error: 'Nao foi possivel validar o convite.'})
  }
  if (!invitation) {
    return response(409, {
      error: 'Nao existe convite pendente para este administrador e clube.',
    })
  }
  if (new Date(String(invitation.expires_at)).getTime() <= Date.now()) {
    return response(409, {error: 'O convite do administrador expirou.'})
  }

  const {data: created, error: createError} =
    await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: `Administrador ${email.split('@')[0]}`,
        user_type: 'admin',
        must_change_password: true,
        must_complete_profile: true,
      },
    })

  if (createError || !created.user) {
    const duplicate = createError?.message.toLowerCase().includes('already')
    return response(duplicate ? 409 : 500, {
      error: duplicate
        ? 'Este e-mail ja possui conta no aplicativo.'
        : (createError?.message ?? 'Nao foi possivel criar a conta.'),
    })
  }

  return response(200, {
    success: true,
    user_id: created.user.id,
    organization_id: organizationId,
    email,
  })
})
