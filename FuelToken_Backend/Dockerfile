# Dockerfile for Odoo 19
FROM odoo:19.0

# Copy custom addons if any
COPY ./addons/ /mnt/extra-addons

USER root
RUN chown -R odoo: /mnt/extra-addons

# Expose necessary ports
EXPOSE 8069 8071 8072

# Set the entry point to start Odoo
ENTRYPOINT ["/entrypoint.sh"]

# CMD can be overridden at runtime but default to Odoo
CMD ["odoo"]