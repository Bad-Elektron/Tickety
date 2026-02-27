import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { RefineProvider } from "@/providers/refine-provider";
import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Tickety Admin",
  description: "Tickety Super Admin Dashboard",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body className={`${inter.variable} font-sans antialiased`}>
        <RefineProvider>{children}</RefineProvider>
      </body>
    </html>
  );
}
