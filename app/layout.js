import './globals.css';
import { AppProvider } from '@/lib/ctx';

export const metadata = {
  title: 'Ración360',
  description: 'Cadena de suministro para contratistas de alimentacion del Estado (PAE, USPEC, ICBF)',
  manifest: '/manifest.webmanifest',
  applicationName: 'Ración360',
  appleWebApp: { capable: true, title: 'Ración360', statusBarStyle: 'default' },
  icons: { icon: [{ url: '/icon.svg', type: 'image/svg+xml' }, { url: '/icon-192.png', sizes: '192x192', type: 'image/png' }], apple: '/icon-192.png' },
};

export const viewport = { width: 'device-width', initialScale: 1, themeColor: '#1f2a44' };

export default function RootLayout({ children }) {
  return (
    <html lang="es">
      <body>
        <AppProvider>{children}</AppProvider>
      </body>
    </html>
  );
}
