# Linux pidfd in Ruby

This repository contains my RubyKaigi 2025 presentation slides on "Bringing Linux pidfd to Ruby." The presentation covers the challenges of process management in Ruby applications and how Linux's pidfd API provides solutions to common race conditions and security issues.

## Key Topics

- Process management challenges in multi-process Ruby applications
- PID reuse problems and race conditions
- Signal handling race conditions
- Linux pidfd API and its benefits for Ruby
- Implementation of pidfd support in Ruby using FFI
- Real-world examples from Karafka and Shoryuken

## View the Presentation

The presentation is available at: [https://mensfeld.github.io/bringing_linux_pidfd_to_ruby](https://mensfeld.github.io/bringing_linux_pidfd_to_ruby)

## Resources

- [Linux pidfd documentation](https://man7.org/linux/man-pages/man2/pidfd_open.2.html)
- [Ruby Feature #19322](https://bugs.ruby-lang.org/issues/19322) - Native pidfd support proposal
- [Karafka](https://github.com/karafka/karafka) - Ruby & Rails Kafka Processing Framework
- [Shoryuken](https://github.com/ruby-shoryuken/shoryuken) - Amazon SQS message processor for Ruby

## Contact

Maciej Mensfeld - [GitHub](https://github.com/mensfeld) - [Twitter](https://twitter.com/mensfeld)

## License

This presentation is available under the MIT license.
