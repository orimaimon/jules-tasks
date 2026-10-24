# Remove the secret token from the print page QR code

The print page no longer embeds `share_token` in the QR code; it now uses the public short id,
like the API does since #49. Added a test that the rendered QR payload contains no token.

Closes #55
