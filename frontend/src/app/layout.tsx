import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Providers } from "@/components/Providers";
import { Header } from "@/components/Header";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "AISandbox",
  description: "Non-custodial ERC-4626 vault managed by AI agents",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body className={`${inter.className} bg-zinc-950 text-white antialiased`}>
        <Providers>
          <Header />
          <main className="mx-auto max-w-7xl px-4 py-6 sm:px-6">
            {children}
          </main>
        </Providers>
      </body>
    </html>
  );
}
