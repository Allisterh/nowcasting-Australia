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
      <p className="mt-2 text-xs text-label max-w-2xl">
        A weekly nowcast of Australian GDP using a dynamic factor model over 13 high-frequency indicators.
      </p>
      <p className="mt-1 text-xs text-label">
        Last updated: {formatDate(generatedAt)}
      </p>
    </header>
  );
}
