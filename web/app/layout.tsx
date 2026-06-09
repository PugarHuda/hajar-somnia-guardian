import type { Metadata } from "next";
import "./globals.css";
import Nav from "./components/Nav";

export const metadata: Metadata = {
  title: "Hajar — Autonomous DeFi Guardian on Somnia",
  description:
    "A multi-tier autonomous security layer for DeFi: deterministic circuit breakers + consensus-verified AI risk scoring on Somnia's Agentic L1.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Nav />
        {children}
      </body>
    </html>
  );
}
