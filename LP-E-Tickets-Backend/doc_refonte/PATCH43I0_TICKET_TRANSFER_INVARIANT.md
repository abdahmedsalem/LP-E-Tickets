# Patch43I0 — Fondation invariant transfert de tickets

Patch43I0 prépare le futur transfert de tickets sans modifier le transfert carnet existant.

Doctrine figée :
- le transfert carnet reste un flux de carnet intact ;
- le transfert ticket sera un flux séparé ;
- un transfert de tickets ne réduit jamais qty_initial sur la ligne source ;
- les faces transférées sortantes sont portées par qty_transferred_out ;
- qty_transferred_out fait partie des buckets protégés dans _controlled_state_fields ;
- la lecture mobile expose qty_transferred_out et amount_transferred_out ;
- un futur fragment destination devra avoir sa propre identité carnet_no / carnet_short_code ;
- le fragment destination devra garder origin_face_line_id et is_transfer_fragment=True ;
- aucun QR, qty_qr_active, qty_qr_blocked, qty_consumed ou qty_expired ne doit être transféré.

Invariant de conservation :

qty_initial = qty_available + qty_qr_active + qty_qr_blocked + qty_consumed + qty_expired + qty_transferred_out

Hors périmètre Patch43I0 :
- pas encore de modèle acpec.fuel.ticket.transfer ;
- pas encore de endpoint mobile de transfert ticket ;
- pas encore de primitive métier complète ;
- pas encore de UI Flutter.
