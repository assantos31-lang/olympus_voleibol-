import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const jsonHeaders = {'Content-Type': 'application/json'}

function response(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), {status, headers: jsonHeaders})
}

function parseEventDate(dateValue: unknown, timeValue: unknown) {
  const dateParts = String(dateValue ?? '').split('/').map(Number)
  const timeParts = String(timeValue ?? '00:00').split(':').map(Number)
  if (dateParts.length !== 3 || dateParts.some(Number.isNaN)) return null
  return new Date(
    dateParts[2],
    dateParts[1] - 1,
    dateParts[0],
    timeParts[0] || 0,
    timeParts[1] || 0,
  )
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return response(405, {error: 'Método inválido.'})

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const cronSecret = Deno.env.get('CLEANUP_CRON_SECRET')
  if (!supabaseUrl || !serviceRoleKey) {
    return response(500, {error: 'Configuração indisponível.'})
  }
  const token = (request.headers.get('Authorization') ?? '')
    .replace(/^Bearer\s+/i, '')
  if (token !== serviceRoleKey && (!cronSecret || token !== cronSecret)) {
    return response(403, {error: 'Acesso negado.'})
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: {persistSession: false, autoRefreshToken: false},
  })
  const reminderLimit = new Date(Date.now() - 24 * 60 * 60 * 1000)
  const {data: workflows, error: workflowError} = await client
    .from('training_planning_workflows')
    .select('event_id, organization_id, last_coordinator_reminder_at')
    .eq('status', 'pending')
    .or(
      `last_coordinator_reminder_at.is.null,last_coordinator_reminder_at.lt.${reminderLimit.toISOString()}`,
    )
  if (workflowError) return response(500, {error: workflowError.message})

  const eventIds = (workflows ?? []).map((row) => row.event_id)
  const {data: events, error: eventError} = eventIds.length === 0
    ? {data: [], error: null}
    : await client
      .from('events')
      .select('id, event_name, event_date, event_time')
      .in('id', eventIds)
  if (eventError) return response(500, {error: eventError.message})
  const eventById = new Map((events ?? []).map((event) => [event.id, event]))

  let sent = 0
  const now = new Date()
  for (const workflow of workflows ?? []) {
    const event = eventById.get(workflow.event_id)
    const eventAt = parseEventDate(event?.event_date, event?.event_time)
    if (!event || !eventAt || eventAt <= now) continue

    const {data: coordinators} = await client
      .from('technical_staff_assignments')
      .select('user_id')
      .eq('organization_id', workflow.organization_id)
      .eq('technical_role', 'technical_coordinator')
      .eq('status', 'active')
      .eq('can_approve_training', true)

    let eventSent = false
    for (const coordinator of coordinators ?? []) {
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
            userId: coordinator.user_id,
            title: 'Planejamento de treino pendente',
            body: `Crie o treino "${event.event_name ?? 'Treino'}" ou libere o planejamento para um técnico.`,
            type: 'training_planning_reminder',
            eventId: workflow.event_id,
          }),
        },
      )
      if (pushResponse.ok) {
        sent += 1
        eventSent = true
      }
    }
    if (eventSent) {
      await client
        .from('training_planning_workflows')
        .update({last_coordinator_reminder_at: now.toISOString()})
        .eq('event_id', workflow.event_id)
        .eq('status', 'pending')
    }
  }

  return response(200, {success: true, sent})
})
