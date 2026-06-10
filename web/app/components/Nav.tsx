"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import Logo from "./Logo";

const LINKS = [
  { href: "/", label: "Overview" },
  { href: "/defense", label: "Defense" },
  { href: "/agents", label: "AI Agents" },
  { href: "/intelligence", label: "Intelligence" },
  { href: "/identity", label: "Identity" },
  { href: "/slide", label: "Deck" },
];

export default function Nav() {
  const path = usePathname();
  if (path === "/slide") return null; // the deck is full-screen
  return (
    <nav className="nav">
      <div className="nav-inner">
        <Link href="/" className="nav-logo">
          <span className="logo"><Logo size={20} /></span> Hajar
        </Link>
        <div className="nav-links">
          {LINKS.map((l) => (
            <Link key={l.href} href={l.href} className={path === l.href ? "active" : ""}>
              {l.label}
            </Link>
          ))}
        </div>
      </div>
    </nav>
  );
}
