const YEAR = new Date().getFullYear()

export default {
  footer: (
    <small style={{ display: 'block', marginTop: '8rem' }}>
      <time>{YEAR}</time> © Aron Beal
      <a href="/feed.xml">RSS</a>

      <div>
        <a href="https://twitter.com/aronbeal">Twitter</a><br />
        <a href="https://github.com/aronbeal">GitHub</a><br />
        <a href="mailto:aron.beal.biz@gmail.com">aron.beal.biz@gmail.com</a>
      </div>

      <style jsx>{`
        a {
          float: right;
        }
        @media screen and (max-width: 480px) {
          article {
            padding-top: 2rem;
            padding-bottom: 4rem;
          }
        }
      `}</style>
    </small>
  )
}
