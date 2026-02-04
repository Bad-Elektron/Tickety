import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const resendApiKey = Deno.env.get('RESEND_API_KEY')

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface SendTicketEmailRequest {
  ticket_id: string
  customer_email: string
  customer_name?: string
}

/**
 * Send a ticket to a customer via email.
 *
 * This function:
 * 1. Retrieves the ticket details
 * 2. Generates a QR code for the ticket
 * 3. Sends an email with the ticket details and QR code
 * 4. Updates the ticket with the customer's email
 */
serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    })

    // Verify the user is authenticated
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body: SendTicketEmailRequest = await req.json()
    const { ticket_id, customer_email, customer_name } = body

    if (!ticket_id || !customer_email) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: ticket_id, customer_email' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRegex.test(customer_email)) {
      return new Response(
        JSON.stringify({ error: 'Invalid email address' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Sending ticket ${ticket_id} to ${customer_email}`)

    // Get ticket details
    const { data: ticket, error: ticketError } = await supabaseAdmin
      .from('tickets')
      .select(`
        id,
        ticket_number,
        qr_code,
        event_id,
        events:event_id (
          id,
          title,
          subtitle,
          date,
          venue,
          city,
          country
        )
      `)
      .eq('id', ticket_id)
      .single()

    if (ticketError || !ticket) {
      console.error('Ticket not found:', ticket_id, ticketError)
      return new Response(
        JSON.stringify({ error: 'Ticket not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify user is staff for this event
    const event = ticket.events as any
    const { data: staffRecord } = await supabaseAdmin
      .from('event_staff')
      .select('id, role')
      .eq('event_id', event.id)
      .eq('user_id', user.id)
      .single()

    if (!staffRecord) {
      // Check if user is the organizer
      const { data: eventRecord } = await supabaseAdmin
        .from('events')
        .select('organizer_id')
        .eq('id', event.id)
        .single()

      if (!eventRecord || eventRecord.organizer_id !== user.id) {
        return new Response(
          JSON.stringify({ error: 'You are not authorized to send tickets for this event' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Format event date
    const eventDate = new Date(event.date)
    const formattedDate = eventDate.toLocaleDateString('en-US', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    })
    const formattedTime = eventDate.toLocaleTimeString('en-US', {
      hour: 'numeric',
      minute: '2-digit',
    })

    // Build location string
    let locationText = ''
    if (event.venue) locationText += event.venue
    if (event.city) locationText += (locationText ? ', ' : '') + event.city
    if (event.country) locationText += (locationText ? ', ' : '') + event.country

    // Generate QR code URL (using quickchart.io for simplicity)
    const qrData = ticket.qr_code || ticket.ticket_number
    const qrCodeUrl = `https://quickchart.io/qr?text=${encodeURIComponent(qrData)}&size=300&dark=000000&light=ffffff`

    // Build email HTML
    const emailHtml = `
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
              line-height: 1.6;
              color: #333;
              max-width: 600px;
              margin: 0 auto;
              padding: 20px;
            }
            .header {
              background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
              color: white;
              padding: 30px;
              border-radius: 12px 12px 0 0;
              text-align: center;
            }
            .header h1 {
              margin: 0;
              font-size: 24px;
            }
            .content {
              background: #f9fafb;
              padding: 30px;
              border-radius: 0 0 12px 12px;
            }
            .ticket-card {
              background: white;
              border-radius: 12px;
              padding: 24px;
              box-shadow: 0 2px 8px rgba(0,0,0,0.1);
              margin-bottom: 20px;
            }
            .event-title {
              font-size: 20px;
              font-weight: bold;
              color: #1f2937;
              margin-bottom: 8px;
            }
            .event-subtitle {
              color: #6b7280;
              margin-bottom: 16px;
            }
            .detail-row {
              display: flex;
              justify-content: space-between;
              padding: 8px 0;
              border-bottom: 1px solid #e5e7eb;
            }
            .detail-row:last-child {
              border-bottom: none;
            }
            .detail-label {
              color: #6b7280;
            }
            .detail-value {
              color: #1f2937;
              font-weight: 500;
            }
            .qr-section {
              text-align: center;
              margin-top: 24px;
            }
            .qr-section img {
              max-width: 200px;
              border-radius: 8px;
              border: 2px solid #e5e7eb;
            }
            .qr-label {
              color: #6b7280;
              font-size: 14px;
              margin-top: 8px;
            }
            .footer {
              text-align: center;
              color: #9ca3af;
              font-size: 12px;
              margin-top: 24px;
            }
          </style>
        </head>
        <body>
          <div class="header">
            <h1>Your Ticket</h1>
          </div>
          <div class="content">
            <div class="ticket-card">
              <div class="event-title">${event.title}</div>
              ${event.subtitle ? `<div class="event-subtitle">${event.subtitle}</div>` : ''}
              <div class="detail-row">
                <span class="detail-label">Date</span>
                <span class="detail-value">${formattedDate}</span>
              </div>
              <div class="detail-row">
                <span class="detail-label">Time</span>
                <span class="detail-value">${formattedTime}</span>
              </div>
              ${locationText ? `
                <div class="detail-row">
                  <span class="detail-label">Location</span>
                  <span class="detail-value">${locationText}</span>
                </div>
              ` : ''}
              <div class="detail-row">
                <span class="detail-label">Ticket #</span>
                <span class="detail-value">${ticket.ticket_number}</span>
              </div>
              <div class="qr-section">
                <img src="${qrCodeUrl}" alt="Ticket QR Code">
                <div class="qr-label">Present this QR code at entry</div>
              </div>
            </div>
            <div class="footer">
              <p>This ticket was sent via Tickety.</p>
              <p>If you didn't request this ticket, please ignore this email.</p>
            </div>
          </div>
        </body>
      </html>
    `

    // Send email via Resend (if API key is available)
    if (resendApiKey) {
      const resendResponse = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${resendApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: 'Tickety <tickets@tickety.app>',
          to: customer_email,
          subject: `Your Ticket for ${event.title}`,
          html: emailHtml,
        }),
      })

      if (!resendResponse.ok) {
        const resendError = await resendResponse.text()
        console.error('Resend API error:', resendError)
        return new Response(
          JSON.stringify({ error: 'Failed to send email' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      console.log('Email sent successfully via Resend')
    } else {
      // Fallback: Log that email would be sent (for development)
      console.log('RESEND_API_KEY not set. Would send email to:', customer_email)
      console.log('Email subject:', `Your Ticket for ${event.title}`)
    }

    // Update ticket with customer email (but don't set owner_id - they need to claim it)
    const { error: updateError } = await supabaseAdmin
      .from('tickets')
      .update({
        owner_email: customer_email,
        delivery_method: 'email',
      })
      .eq('id', ticket_id)

    if (updateError) {
      console.error('Failed to update ticket:', updateError)
      // Don't fail the request - email was already sent
    }

    // Update cash transaction if exists
    await supabaseAdmin
      .from('cash_transactions')
      .update({
        customer_email: customer_email,
        customer_name: customer_name || null,
        delivery_method: 'email',
      })
      .eq('ticket_id', ticket_id)

    return new Response(
      JSON.stringify({
        success: true,
        email_sent: !!resendApiKey,
        message: resendApiKey
          ? `Ticket sent to ${customer_email}`
          : `Email delivery simulated (RESEND_API_KEY not configured)`,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error: unknown) {
    console.error('Error sending ticket email:', error)
    const errorMessage = error instanceof Error ? error.message : 'Internal server error'
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
