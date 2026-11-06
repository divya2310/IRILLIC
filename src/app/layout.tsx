import type { Metadata, Viewport } from "next";
import { getBranding } from "@/lib/branding";
import "@/app/globals.css";

export const dynamic = "force-dynamic";

export async function generateMetadata(): Promise<Metadata> {
  const branding = await getBranding();
  return {
    title: {
      default: branding.seoTitle,
      template: `%s | ${branding.siteName}`,
    },
    description: branding.seoDescription,
    keywords: branding.seoKeywords,
    icons: { icon: branding.favicon },
  };
}

export async function generateViewport(): Promise<Viewport> {
  const { themeColor } = await getBranding();
  return { themeColor };
}

/* Enables Theme 1 scroll reveals only when JavaScript runs (no hidden content without JS) */
const enableJsClass = "document.documentElement.classList.add('js');";

/**
 * The document shell only. The public website's header, footer and theme live
 * in the site layout; the panel brings its own in the dashboard and auth
 * layouts. Keeping them apart means neither downloads the other's stylesheet.
 */
export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: enableJsClass }} />
      </head>
      <body className="font-sans antialiased" suppressHydrationWarning>{children}</body>
    </html>
  );
}
