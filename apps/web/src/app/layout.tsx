// Next.js requires a root layout to keep App Router API handlers registered in
// development. There is intentionally no browser page; this layout is only the
// invisible routing shell for the native app's headless local service.
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
