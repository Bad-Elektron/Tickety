-- Extend block_private_ticket_resale() to also block unminted NFT tickets
CREATE OR REPLACE FUNCTION block_private_ticket_resale()
RETURNS TRIGGER AS $$
DECLARE
    t_mode TEXT;
    t_nft_minted BOOLEAN;
    t_nft_burned BOOLEAN;
    e_nft_enabled BOOLEAN;
BEGIN
    SELECT t.ticket_mode, t.nft_minted, t.nft_burned, e.nft_enabled
    INTO t_mode, t_nft_minted, t_nft_burned, e_nft_enabled
    FROM tickets t
    JOIN events e ON e.id = t.event_id
    WHERE t.id = NEW.ticket_id;

    IF t_mode = 'private' THEN
        RAISE EXCEPTION 'Private tickets cannot be listed for resale';
    END IF;

    IF t_nft_burned = true THEN
        RAISE EXCEPTION 'This ticket NFT has expired and cannot be resold';
    END IF;

    IF (t_mode = 'public' OR e_nft_enabled = true)
       AND (t_nft_minted IS NULL OR t_nft_minted = false) THEN
        RAISE EXCEPTION 'Ticket is still being prepared and cannot be resold yet';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
