import { formatDate } from "@/lib/format";

interface HeaderProps {
  generatedAt: string;
}

export default function Header({ generatedAt }: HeaderProps) {
  return (
    <header className="border-b border-border-heavy pb-4 mb-6">
      <h1 className="font-headline text-4xl sm:text-5xl text-black">
        Australia GDP nowcast
      </h1>
      <p className="mt-2 text-xs text-label">
        This nowcast is a real-time estimate of GDP growth for the latest quarter, produced before the ABS publishes the official figure with a roughly 3-month lag after the end of the quarter.
      </p>
      <p className="mt-1 text-xs text-label">
        Last updated: {formatDate(generatedAt)}
      </p>
    </header>
  );
}
