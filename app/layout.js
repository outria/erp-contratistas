import './globals.css';
import { AppProvider } from '@/lib/ctx';

export const metadata = {
  title: 'Supply ERP',
  description: 'Cadena de suministro para contratistas de alimentacion del Estado (PAE, USPEC, ICBF)',
  manifest: '/manifest.webmanifest',
  applicationName: 'Supply ERP',
  appleWebApp: { capable: true, title: 'Supply ERP', statusBarStyle: 'default' },
  icons: { icon: '/icon-192.png', apple: '/icon-192.png' },
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
