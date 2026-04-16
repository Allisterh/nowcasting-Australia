export default function Footer() {
  return (
    <footer className="mt-16 pt-4 border-t border-border text-xs text-label-light flex flex-wrap gap-x-4 gap-y-1">
      <span>Not an official forecast</span>
      <span>·</span>
      <span>Chart: 𝕏 @jameswilson</span>
      <span>·</span>
      <a href="https://github.com/adrasyn/nowcasting" className="hover:text-label underline-offset-2 hover:underline">
        Source on GitHub
      </a>
      <span>·</span>
      <a href="#methodology" className="hover:text-label underline-offset-2 hover:underline">
        Methodology
      </a>
    </footer>
  );
}
