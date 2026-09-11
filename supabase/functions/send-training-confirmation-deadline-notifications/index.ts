import {createClient} from 'https://esm.sh/@supabase/supabase-js@2'

const jsonHeaders = {'Content-Type': 'application/json'}

function response(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {status, headers: jsonHeaders})
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return response(405, {error: 'Método inválido.'})

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const cronSecret = Deno.env.get('CLEANUP_CRON_SECRET')
  if (!supabaseUrl || !serviceRoleKey) {
    return response(500, {error: 'Configuração indisponível.'})
  }

  const cronToken = request.headers.get('x-cron-secret') ?? ''
  if (!cronSecret || cronToken !== cronSecret) {
    return response(403, {error: 'Acesso negado.'})
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: {persistSession: false, autoRefreshToken: false},
  })
  const {data: dueRows, error: claimError} = await client.rpc(
    'claim_expired_event_confirmations_v2',
    {p_limit: 100},
  )
  if (claimError) return response(500, {error: claimError.message})

  let sent = 0
  let failed = 0
  for (const row of dueRows ?? []) {
    try {
      const eventType = ['amistoso', 'campeonato'].includes(row.event_type)
        ? row.event_type
        : 'treino'
      const pushResponse = await fetch(
        `${supabaseUrl}/functions/v1/send-push-notification`,
        {
          method: 'POST',
          headers: {
            ...jsonHeaders,
            Authorization: `Bearer ${serviceRoleKey}`,
            apikey: serviceRoleKey,
          },
          body: JSON.stringify({
            userId: row.user_id,
            title: 'Prazo de confirmação encerrado',
            body: `O prazo para confirmar sua presença neste ${eventType} expirou. Como sua presença não foi confirmada dentro do período permitido, você não deverá comparecer ao ${eventType}.`,
            type: 'event_confirmation_deadline_expired',
            eventId: row.event_id,
          }),
        },
      )
      if (!pushResponse.ok) {
        throw new Error(`Falha no push (${pushResponse.status})`)
      }
      await client
        .from('training_confirmation_deadline_notifications')
        .update({sent_at: new Date().toISOString(), last_error: null})
        .eq('convocation_id', row.convocation_id)
        .is('sent_at', null)
      sent += 1
    } catch (error) {
      failed += 1
      await client
        .from('training_confirmation_deadline_notifications')
        .update({
          claimed_at: null,
          last_error: error instanceof Error ? error.message : String(error),
        })
        .eq('convocation_id', row.convocation_id)
        .is('sent_at', null)
    }
  }

  return response(200, {success: true, claimed: dueRows?.length ?? 0, sent, failed})
})
